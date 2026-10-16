import Combine
import CoreGraphics
import Foundation
import LocalAuthentication
import OSLog
import SwiftUI

/// Owns a single camera session and one pending authorization. Results never release a
/// protected action until both identity and a fresh liveness challenge have passed.
@MainActor
final class FaceCheckController: ObservableObject, FaceCheckAuthorizing {
    static let shared = FaceCheckController()
    enum CameraState: Equatable { case off, starting, on, denied, unavailable }
    enum Activity: Equatable { case watching, enrolling, testing, saving }

    struct TestOutcome: Equatable {
        var matched: Bool
        var name: String?
        var distance: Float?
        var limit: Float
    }

    static let testDuration: TimeInterval = 10
    private static let presetKey = "faceCheck.matchPreset"
    private let logger = Logger(subsystem: "com.local.Notchy", category: "FaceCheck")

    @Published private(set) var cameraState: CameraState = .off
    @Published private(set) var activity: Activity = .watching
    @Published private(set) var face: FaceFrameObservation?
    @Published private(set) var chip: CGImage?
    @Published private(set) var liveDistance: Float?
    @Published private(set) var status = ""
    @Published private(set) var problem: String?
    @Published private(set) var identities: [FaceIdentity] = []
    @Published private(set) var storeProblem: String?
    @Published private(set) var poseCounts: [FaceEnrollmentPose: Int] = [:]
    @Published private(set) var testOutcome: TestOutcome?
    @Published private(set) var enrollmentIsLive = false
    @Published var preset: FaceMatchPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
            rebuildMatcher()
        }
    }

    let camera: any FaceCheckCameraCapturing
    let liveActivity: FaceCheckLiveActivity
    var onBeginCheck: (() -> Void)?
    var onSaved: (() -> Void)?
    var onNeedsEnrollment: (() -> Void)?

    private let embedder = FaceEmbedder()
    private lazy var pipeline = FaceCheckPipeline(embedder: embedder)
    private var store: FaceEnrollmentStore?
    private var matcher: FaceMatcher?
    private var tracker: FaceEnrollmentPoseTracker?
    private var enrollmentLiveness = FaceLivenessTracker(direction: .left)
    private var enrollmentAnchor: [Float]?
    private var enrollmentLastFrame: TimeInterval?
    private var enrolmentName = ""
    private var verification: FaceVerificationSession?
    private var testClosest: FaceMatchScore?
    private var challengeStartedAt: TimeInterval?
    private var authorization: FaceAuthorizationRequest?
    private var requestEpoch = 0
    private var attempt = 0
    private var deadline: Task<Void, Never>?
    private var generation = 0
    private var previews = Set<UUID>()
    private var retryReason: String?
    private var preparingRequest = false
    private let checkTimeout: Duration

    init(store: FaceEnrollmentStore? = nil, liveActivity: FaceCheckLiveActivity? = nil,
         camera: any FaceCheckCameraCapturing = FaceCheckCamera(),
         checkTimeout: Duration = .seconds(FaceCheckController.testDuration)) {
        self.store = store
        self.camera = camera
        self.checkTimeout = checkTimeout
        self.liveActivity = liveActivity ?? FaceCheckLiveActivity()
        preset = UserDefaults.standard.string(forKey: Self.presetKey).flatMap(FaceMatchPreset.init(rawValue:)) ?? .standard
        self.liveActivity.onRetry = { [weak self] in self?.retry() }
        self.liveActivity.onCancel = { [weak self] in self?.cancelVerification() }
        self.liveActivity.onExpired = { [weak self] in self?.expireResult() }
    }

    var samplesPerPose: Int { FaceEnrollmentRules.standard.samplesPerPose }
    var canFinishEnrolmentEarly: Bool {
        enrollmentIsLive && (poseCounts[.centre] ?? 0) > 0
            && enrollmentLastFrame.map { ProcessInfo.processInfo.systemUptime - $0 < 1 } == true
    }

    // MARK: Camera ownership

    func retainPreview(_ id: UUID, start: Bool) {
        previews.insert(id)
        if start { startCamera() }
    }

    func releasePreview(_ id: UUID) {
        previews.remove(id)
        if previews.isEmpty, activity == .enrolling { cancelEnrolment() }
        stopCameraIfUnused()
    }

    func startCamera() {
        guard cameraState == .off || cameraState == .denied || cameraState == .unavailable else { return }
        generation &+= 1
        let current = generation
        cameraState = .starting
        problem = nil
        Task { [weak self] in
            guard let self else { return }
            let allowed: Bool
            switch self.camera.authorizationStatus {
            case .authorized: allowed = true
            case .notDetermined: allowed = await self.camera.requestAuthorization()
            default: allowed = false
            }
            guard self.generation == current else { return }
            guard allowed else {
                self.cameraState = .denied
                self.cameraFailed("Allow camera access in System Settings, then retry.")
                return
            }
            let pipeline = self.pipeline
            self.camera.start(onFrame: { [weak self] image, capturedAt in
                var analysis = await pipeline.analyze(image)
                analysis.capturedAt = capturedAt
                await self?.handle(analysis, generation: current)
            }, completion: { [weak self] running in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.cameraState = running ? .on : .unavailable
                    if !running { self.cameraFailed("No camera is available. Connect a camera and retry.") }
                }
            })
        }
    }

    func stopCamera() {
        cancelVerification()
        if activity == .enrolling { cancelEnrolment() }
        stopCapture()
    }

    private func stopCapture() {
        generation &+= 1
        camera.stop()
        cameraState = .off
        face = nil
        chip = nil
        liveDistance = nil
        let current = generation
        Task { [weak self] in
            guard let self, self.generation == current, self.cameraState == .off else { return }
            await self.embedder.unload()
        }
    }

    private func stopCameraIfUnused() {
        if previews.isEmpty, activity != .enrolling, activity != .testing { stopCapture() }
    }

    private func cameraFailed(_ message: String) {
        problem = message
        if activity == .testing { finishTest(matched: nil, message: message) }
        else if activity == .enrolling {
            cancelEnrolment()
            status = message
        }
    }

    // MARK: Store

    func loadIdentities() { Task { await refreshIdentities() } }

    @discardableResult
    private func refreshIdentities() async -> Bool {
        guard let store = makeStore() else { return false }
        switch await store.load() {
        case .ready(let loaded):
            identities = loaded
            storeProblem = nil
            rebuildMatcher()
            return true
        case .unreadable(let reason):
            identities = []
            storeProblem = Self.describe(reason)
        case .notLoaded:
            identities = []
            storeProblem = "The saved faces have not loaded."
        }
        rebuildMatcher()
        return false
    }

    func deleteIdentity(_ identity: FaceIdentity) {
        authorize(reason: "Delete saved face", requiresEnrollment: true) { [weak self] allowed in
            guard allowed, let self else { return }
            Task {
                guard let store = self.makeStore() else { return }
                do {
                    try await store.removeIdentity(id: identity.id)
                    await self.refreshIdentities()
                } catch { self.storeProblem = "Could not delete the saved face: \(error.localizedDescription)" }
            }
        }
    }

    /// An unreadable store can be reset after macOS authenticates the owner. The app never
    /// stores or types a login password.
    func deleteAllFaceData() {
        Task {
            let readable = await refreshIdentities()
            if !readable || (!identities.isEmpty && matcher?.hasComparableIdentities != true) {
                let context = LAContext()
                guard (try? await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Reset the unavailable Face Check data in Notchy."
                )) == true else { return }
                await eraseFaceData()
            } else {
                authorize(reason: "Delete all saved faces", requiresEnrollment: false) { [weak self] allowed in
                    guard allowed else { return }
                    Task { await self?.eraseFaceData() }
                }
            }
        }
    }

    private func eraseFaceData() async {
        guard let store = makeStore() else { return }
        do {
            try await store.deleteAll()
            testOutcome = nil
            await refreshIdentities()
        } catch { storeProblem = "Could not delete the face data: \(error.localizedDescription)" }
    }

    private func makeStore() -> FaceEnrollmentStore? {
        if let store { return store }
        do {
            let created = FaceEnrollmentStore(
                fileURL: try FaceEnrollmentStore.defaultFileURL(),
                keyProvider: try FaceCheckKeyStorage.standard()
            )
            store = created
            return created
        } catch {
            storeProblem = "Face Check's storage is unavailable: \(error.localizedDescription)"
            return nil
        }
    }

    private func rebuildMatcher() {
        matcher = FaceMatcher(identities: identities, modelIdentifier: FaceEmbedder.modelIdentifier, maximumDistance: preset.maximumDistance)
    }

    // MARK: Enrollment

    func startEnrolment(name: String) {
        guard activity == .watching, !preparingRequest else { return }
        authorize(reason: "Add a saved face", requiresEnrollment: false) { [weak self] allowed in
            guard allowed, let self else { return }
            self.beginEnrolment(name: name)
        }
    }

    private func beginEnrolment(name: String) {
        liveActivity.dismiss()
        retryReason = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        enrolmentName = String((trimmed.isEmpty ? "Me" : trimmed).prefix(80))
        tracker = FaceEnrollmentPoseTracker(modelIdentifier: FaceEmbedder.modelIdentifier)
        enrollmentLiveness = FaceLivenessTracker(direction: Bool.random() ? .left : .right)
        enrollmentAnchor = nil
        enrollmentLastFrame = nil
        enrollmentIsLive = false
        poseCounts = [:]
        testOutcome = nil
        activity = .enrolling
        challengeStartedAt = ProcessInfo.processInfo.systemUptime
        status = "Look straight at the camera, then blink."
        startCamera()
        onNeedsEnrollment?()
    }

    func cancelEnrolment() {
        tracker = nil
        enrollmentAnchor = nil
        enrollmentLastFrame = nil
        enrollmentIsLive = false
        poseCounts = [:]
        activity = .watching
        status = ""
        stopCameraIfUnused()
    }

    func finishEnrolment() {
        guard let tracker, canFinishEnrolmentEarly, activity == .enrolling else { return }
        let identity = tracker.makeIdentity(name: enrolmentName) ?? FaceIdentity(name: enrolmentName, samples: tracker.samples)
        self.tracker = nil
        activity = .saving
        status = "Saving your face…"
        Task {
            guard let store = makeStore() else {
                activity = .watching
                return
            }
            do {
                try await store.upsert(identity)
                await refreshIdentities()
                activity = .watching
                status = "Face saved. You can use Check now."
                poseCounts = [:]
                enrollmentIsLive = false
                liveActivity.finish(saved: true, recognized: true, message: "Ready for your next check")
                onSaved?()
                stopCameraIfUnused()
                logger.info("Face enrollment saved")
            } catch {
                activity = .watching
                storeProblem = "Could not save your face: \(error.localizedDescription)"
                status = "Your face was not saved."
                stopCameraIfUnused()
            }
        }
    }

    // MARK: Authorization

    func authorize(reason: String, requiresEnrollment: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        guard activity != .enrolling, activity != .saving else { completion(false); return }
        requestEpoch &+= 1
        let currentRequest = requestEpoch
        cancelVerification()
        // A displaced completion may synchronously request a newer action. The newest caller
        // owns the check; never overwrite its callback or leave this caller unresolved.
        guard requestEpoch == currentRequest else { completion(false); return }
        let request = FaceAuthorizationRequest(completion: completion)
        authorization = request
        preparingRequest = true
        Task { [weak self] in
            guard let self else { request.resolve(false); return }
            let ready = await self.refreshIdentities()
            guard self.authorization === request, !request.isResolved else { return }
            self.preparingRequest = false
            guard ready else {
                self.status = self.storeProblem ?? "Saved faces are unavailable."
                self.resolveAuthorization(false)
                return
            }
            guard self.matcher?.hasComparableIdentities == true else {
                if requiresEnrollment {
                    self.status = "Save your face in the Face tab first."
                    self.resolveAuthorization(false)
                    self.onNeedsEnrollment?()
                } else if self.identities.isEmpty {
                    self.resolveAuthorization(true)
                } else {
                    // An incompatible or disabled enrollment is not an empty store.
                    self.status = "Reset saved faces in Face Check settings, then enroll again."
                    self.resolveAuthorization(false)
                }
                return
            }
            self.beginTest(reason: reason)
        }
    }

    func startTest() {
        guard activity == .watching, !preparingRequest else { return }
        authorize(reason: "Face Check", requiresEnrollment: true) { _ in }
    }

    private func beginTest(reason: String) {
        guard let matcher, matcher.hasComparableIdentities else { resolveAuthorization(false); return }
        attempt &+= 1
        let current = attempt
        deadline?.cancel()
        retryReason = reason
        testOutcome = nil
        testClosest = nil
        verification = FaceVerificationSession(matcher: matcher, direction: Bool.random() ? .left : .right)
        activity = .testing
        challengeStartedAt = ProcessInfo.processInfo.systemUptime
        status = "Look at the camera, then blink."
        liveActivity.begin(reason: reason)
        onBeginCheck?()
        guard attempt == current, activity == .testing, verification != nil else { return }
        startCamera()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: self?.checkTimeout ?? .seconds(Self.testDuration))
            guard !Task.isCancelled, let self, self.attempt == current, self.activity == .testing else { return }
            self.finishTest(matched: nil, message: "Check timed out. Look at the camera and follow the prompt.")
        }
        logger.info("Face check started")
    }

    private func retry() {
        guard activity == .watching, let reason = retryReason else { return }
        beginTest(reason: reason)
    }

    func cancelVerification() {
        attempt &+= 1
        deadline?.cancel()
        deadline = nil
        verification = nil
        retryReason = nil
        preparingRequest = false
        if activity == .testing { activity = .watching }
        liveActivity.dismiss()
        resolveAuthorization(false)
        stopCameraIfUnused()
    }

    func cancelAuthorization() { cancelVerification() }

    private func expireResult() {
        retryReason = nil
        resolveAuthorization(false)
        stopCameraIfUnused()
    }

    private func resolveAuthorization(_ allowed: Bool) {
        let request = authorization
        authorization = nil
        request?.resolve(allowed)
    }

    private func finishTest(matched: FaceMatchScore?, message: String) {
        guard activity == .testing else { return }
        deadline?.cancel()
        deadline = nil
        verification = nil
        let closest = matched ?? testClosest
        let name = matched.flatMap { score in identities.first { $0.id == score.identityID }?.name }
        testOutcome = TestOutcome(matched: matched != nil, name: name, distance: closest?.templateDistance, limit: preset.maximumDistance)
        activity = .watching
        status = message
        liveActivity.finish(recognized: matched != nil, message: message)
        stopCameraIfUnused()
        if matched != nil {
            retryReason = nil
            resolveAuthorization(true)
            logger.info("Face check passed")
        } else {
            // Keep the original request for a deliberate retry; timeout/cancel completes it false.
            logger.info("Face check failed")
        }
    }

    // MARK: Frames

    private func handle(_ analysis: FaceFrameAnalysis, generation frameGeneration: Int) {
        guard frameGeneration == generation, cameraState == .on || cameraState == .starting else { return }
        face = analysis.face
        chip = analysis.chip
        problem = analysis.problem
        let now = ProcessInfo.processInfo.systemUptime
        if activity == .testing || activity == .enrolling {
            guard let capturedAt = analysis.capturedAt, capturedAt.isFinite,
                  capturedAt >= (challengeStartedAt ?? .infinity) else { return }
            guard now - capturedAt >= 0, now - capturedAt <= 1 else {
                if activity == .testing {
                    finishTest(matched: nil, message: "The camera was interrupted. Please retry.")
                } else {
                    _ = enrollmentLiveness.consume(nil, timestamp: now)
                    enrollmentIsLive = false
                }
                return
            }
        }
        let frameTime = analysis.capturedAt ?? now
        switch activity {
        case .watching:
            if let descriptor = analysis.descriptor, let matcher {
                liveDistance = matcher.match(descriptor).scores.first?.templateDistance
            } else { liveDistance = nil }
        case .saving: break
        case .enrolling: feedEnrolment(analysis, timestamp: frameTime)
        case .testing:
            guard var verification else { return }
            let result = verification.consume(analysis, timestamp: frameTime)
            self.verification = verification
            testClosest = verification.closest
            liveDistance = verification.closest?.templateDistance
            switch result {
            case .waiting(let message):
                status = message
                liveActivity.update(prompt: message)
            case .recognized(let score):
                finishTest(matched: score, message: "It's \(identities.first { $0.id == score.identityID }?.name ?? "you").")
            case .rejected(let message):
                finishTest(matched: nil, message: message)
            }
        }
    }

    private func feedEnrolment(_ analysis: FaceFrameAnalysis, timestamp: TimeInterval) {
        guard var tracker else { return }
        if let denial = analysis.liveness?.denial {
            cancelEnrolment()
            status = denial.message
            return
        }
        guard analysis.faceCount == 1, let face = analysis.face, let descriptor = analysis.descriptor,
              FaceDescriptor.isUsable(descriptor), let yaw = face.yaw, let pitch = face.pitch,
              face.quality >= 0.3 else {
            _ = enrollmentLiveness.consume(nil, timestamp: timestamp)
            enrollmentIsLive = false
            enrollmentLastFrame = nil
            _ = tracker.noFace()
            self.tracker = tracker
            status = analysis.faceCount > 1 ? "Only one person should be in view." : "Look at the camera in good light."
            return
        }
        if let anchor = enrollmentAnchor, FaceDescriptor.distance(anchor, descriptor) > 0.6 {
            cancelEnrolment()
            status = "The face changed. Start a new scan."
            return
        }
        if enrollmentAnchor == nil { enrollmentAnchor = descriptor }
        switch enrollmentLiveness.consume(analysis.liveness, timestamp: timestamp) {
        case .rejected(let failure):
            cancelEnrolment()
            status = failure.message
            return
        case .collecting(let prompt):
            enrollmentIsLive = false
            status = prompt.message
            return
        case .passed:
            enrollmentIsLive = true
            enrollmentLastFrame = timestamp
        }
        // Vision's positive pitch is a downward nod; the enrollment grid uses positive up.
        let event = tracker.process(FaceEnrollmentFrame(yaw: yaw, pitch: -pitch, quality: face.quality, descriptor: descriptor, timestamp: timestamp))
        self.tracker = tracker
        poseCounts = Dictionary(uniqueKeysWithValues: FaceEnrollmentPose.allCases.map { ($0, tracker.capturedCount(for: $0)) })
        status = Self.describe(event, next: tracker.suggestedPose)
        if tracker.isComplete { finishEnrolment() }
    }

    // MARK: Text

    static func describe(_ event: FaceEnrollmentEvent, next: FaceEnrollmentPose?) -> String {
        switch event {
        case .noFace: "Looking for your face…"
        case .unusableDescriptor: "Hold still…"
        case .betweenPoses: "Keep turning slowly…"
        case .lowQuality: "Move closer or into better light."
        case .centreFirst: "Look straight at the camera first."
        case .poseAlreadyCaptured: next.map { "Now \(instruction(for: $0))." } ?? "Almost done…"
        case .holding: "Hold it…"
        case .waitingForVariation: "Move a little…"
        case .differentFace: "That doesn't look like the same face. Look straight at the camera."
        case .captured: next.map { "Got it. Now \(instruction(for: $0))." } ?? "Got it."
        case .complete: "All poses captured."
        }
    }

    static func instruction(for pose: FaceEnrollmentPose) -> String {
        switch pose {
        case .centre: "look straight at the camera"
        case .left, .right: "turn your head a little to the side"
        case .up: "tilt your head up a little"
        case .down: "tilt your head down a little"
        case .upLeft, .upRight: "look up and to the side"
        case .downLeft, .downRight: "look down and to the side"
        }
    }

    static func describe(_ reason: FaceEnrollmentUnreadableReason) -> String {
        switch reason {
        case .keyMissing: "The saved faces can't be opened because their key is gone. Delete the face data and enrol again."
        case .keyUnavailable(let detail): "The key for the saved faces is unavailable (\(detail))."
        case .fileUnavailable(let detail): "The saved faces can't be read (\(detail))."
        case .cannotDecrypt: "The saved faces can't be decrypted. Delete the face data and enrol again."
        case .damaged: "The saved faces are damaged. Delete the face data and enrol again."
        case .unsupportedVersion(let version): "The saved faces were written by a newer Notchy (format \(version))."
        }
    }
}
