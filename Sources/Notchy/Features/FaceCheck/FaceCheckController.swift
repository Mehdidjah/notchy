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
    static let shared = FaceCheckController(preferences: .shared)
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
    @Published private(set) var isPreparingEnrollment = false
    private(set) var isMacUnlockEnrollment = false
    @Published var preset: FaceMatchPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
            rebuildMatcher()
        }
    }

    let camera: any FaceCheckCameraCapturing
    let liveActivity: FaceCheckLiveActivity
    var onBeginCheck: (() -> Void)?
    var onSaved: ((FaceIdentity) -> Void)?
    var onNeedsEnrollment: (() -> Void)?
    var onEnrollmentEnded: ((String?) -> Void)?

    private let recognitionProfile = FaceModelValidation.activeProfile
    private let enrollmentProfile = FaceRecognitionProfile.auraFace
    private let embedder = FaceEmbedder(profile: FaceModelValidation.activeProfile)
    private lazy var pipeline = FaceCheckPipeline(embedder: embedder)
    private var store: FaceEnrollmentStore?
    private var matcher: FaceMatcher?
    private var tracker: FaceEnrollmentPoseTracker?
    private var enrollmentAnchor: [Float]?
    private var enrollmentLastFrame: TimeInterval?
    private var lastEnrollmentLogAt: TimeInterval = 0
    private var lastEnrollmentLogState = ""
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
    private let enrollmentOwnerAuthorization: @MainActor () async -> Bool
    private var enrollmentOwnerTask: Task<Void, Never>?
    private var enrollmentOwnerEpoch = 0
    private var enrollmentOwnerGranted = false
    private var recapturingIdentity: FaceIdentity?
    private let preferences: FaceCheckPreferences?
    private var preferenceObserver: AnyCancellable?

    init(store: FaceEnrollmentStore? = nil, liveActivity: FaceCheckLiveActivity? = nil,
         camera: any FaceCheckCameraCapturing = FaceCheckCamera(),
         checkTimeout: Duration = .seconds(FaceCheckController.testDuration),
         preferences: FaceCheckPreferences? = nil,
         enrollmentOwnerAuthorization: @escaping @MainActor () async -> Bool = {
             let context = LAContext()
             return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                 localizedReason: "Set up a face for Mac unlock in Notchy.")) == true
         }) {
        self.store = store
        self.preferences = preferences
        self.camera = camera
        self.checkTimeout = checkTimeout
        self.enrollmentOwnerAuthorization = enrollmentOwnerAuthorization
        self.liveActivity = liveActivity ?? FaceCheckLiveActivity()
        self.liveActivity.previewSession = camera.session
        preset = UserDefaults.standard.string(forKey: Self.presetKey).flatMap(FaceMatchPreset.init(rawValue:)) ?? .standard
        self.liveActivity.onRetry = { [weak self] in self?.retry() }
        self.liveActivity.onCancel = { [weak self] in self?.cancelVerification() }
        self.liveActivity.onExpired = { [weak self] in self?.expireResult() }
        preferenceObserver = preferences?.$options.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            let wasPreviewing = cameraState == .on && activity == .watching && !previews.isEmpty
            // Revoke old results synchronously; Published updates its stored value afterward.
            stopCamera()
            let token = generation
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                rebuildMatcher()
                if wasPreviewing, !previews.isEmpty { startCamera() }
            }
        }
    }

    var samplesPerPose: Int { FaceEnrollmentRules.standard.samplesPerPose }
    var matchingDistanceLimit: Float {
        preferences?.options.maximumDistance(profile: recognitionProfile, validated: FaceModelValidation.bundled?.isAccepted == true)
            ?? recognitionProfile.maximumDistance(for: preset)
    }
    var usesCalibratedThreshold: Bool { FaceModelValidation.bundled != nil }
    var enrollmentInstruction: String {
        if let problem { return problem }
        return status.isEmpty ? FaceEnrollmentPresentation.instruction(for: .centre) : status
    }
    var canFinishEnrolmentEarly: Bool {
        enrollmentIsLive && tracker?.isComplete == true
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
        let options = preferences?.options ?? FaceCheckOptions()
        camera.selectCamera(id: FaceCheckDisplay.cameraID(options: options))
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
                let enrolling = await self?.activity == .enrolling
                let analysis = await pipeline.analyze(image, capturedAt: capturedAt, generation: current,
                                                      enrolling: enrolling, minimumFaceWidth: options.minimumFaceWidth)
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
            await self.pipeline.unload()
        }
    }

    private func stopCameraIfUnused() {
        if previews.isEmpty, activity != .enrolling, activity != .testing { stopCapture() }
    }

    private func cameraFailed(_ message: String) {
        problem = message
        if activity == .testing { finishTest(matched: nil, message: message) }
        else if activity == .enrolling {
            endEnrolment(message: message)
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
        if matcher?.hasComparableIdentities != true {
            Task {
                guard await enrollmentOwnerAuthorization() else { return }
                await removeSavedIdentity(identity)
            }
            return
        }
        authorize(reason: "Delete saved face", requiresEnrollment: true) { [weak self] allowed in
            guard allowed, let self else { return }
            Task { await self.removeSavedIdentity(identity) }
        }
    }

    private func removeSavedIdentity(_ identity: FaceIdentity) async {
        guard let store = makeStore() else { return }
        do {
            try await store.removeIdentity(id: identity.id)
            await refreshIdentities()
        } catch { storeProblem = "Could not delete the saved face: \(error.localizedDescription)" }
    }

    func setIdentityEnabled(_ enabled: Bool, identity: FaceIdentity) {
        guard activity == .watching, !isPreparingEnrollment else { return }
        Task {
            // Disabling is immediate; restoring an identity requires the account owner.
            if enabled, !identity.isEnabled, !(await enrollmentOwnerAuthorization()) { return }
            guard let store = makeStore() else { return }
            do {
                try await store.setEnabled(enabled, id: identity.id)
                cancelVerification()
                await refreshIdentities()
            } catch { storeProblem = "Could not update the saved face: \(error.localizedDescription)" }
        }
    }

    /// An unreadable store can be reset after macOS authenticates the owner.
    /// Replacing the enrolled identity invalidates any separate Mac unlock credential binding.
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
        matcher = FaceMatcher(identities: identities, profile: recognitionProfile,
                              maximumDistance: matchingDistanceLimit)
    }

    // MARK: Enrollment

    func startEnrolment(name: String) {
        guard activity == .watching, !preparingRequest, !isPreparingEnrollment else { return }
        authorize(reason: "Add a saved face", requiresEnrollment: false) { [weak self] allowed in
            guard allowed, let self else { return }
            self.recapturingIdentity = nil
            self.beginEnrolment(name: name)
        }
    }

    /// Changing an existing enrollment uses macOS owner authentication. It does not send
    /// setup through the in-app face-verification presentation or trust an old template.
    func startMacUnlockEnrolment(name: String = "Me", replacing identity: FaceIdentity? = nil) {
        guard activity == .watching, !preparingRequest, !isPreparingEnrollment else { return }
        cancelVerification()
        isPreparingEnrollment = true
        let token = enrollmentOwnerEpoch
        enrollmentOwnerTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if enrollmentOwnerEpoch == token {
                    isPreparingEnrollment = false
                    enrollmentOwnerTask = nil
                }
            }
            let readable = await refreshIdentities()
            guard enrollmentOwnerEpoch == token, !Task.isCancelled else { return }
            guard readable else { status = storeProblem ?? "Saved faces are unavailable."; return }
            let allowed = identities.isEmpty ? true : await enrollmentOwnerAuthorization()
            guard enrollmentOwnerEpoch == token, !Task.isCancelled else { return }
            guard allowed else { status = "Face Unlock setup was cancelled."; return }
            recapturingIdentity = identity
            enrollmentOwnerGranted = true
            beginEnrolment(name: name, forMacUnlock: true)
        }
    }

    func cancelMacUnlockEnrolmentAuthorization() {
        enrollmentOwnerEpoch &+= 1
        enrollmentOwnerTask?.cancel()
        enrollmentOwnerTask = nil
        enrollmentOwnerGranted = false
        isPreparingEnrollment = false
    }

    private func beginEnrolment(name: String, forMacUnlock: Bool = false) {
        isMacUnlockEnrollment = forMacUnlock
        liveActivity.dismiss()
        retryReason = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        enrolmentName = String((trimmed.isEmpty ? "Me" : trimmed).prefix(80))
        var rules = FaceEnrollmentRules.standard
        rules.descriptorDimension = enrollmentProfile.dimension
        rules.samePersonMaximumDistance = enrollmentProfile.enrollmentDistance
        tracker = FaceEnrollmentPoseTracker(modelIdentifier: enrollmentProfile.identifier,
                                             rules: rules, profile: enrollmentProfile)
        enrollmentAnchor = nil
        enrollmentLastFrame = nil
        enrollmentIsLive = false
        poseCounts = [:]
        testOutcome = nil
        activity = .enrolling
        challengeStartedAt = ProcessInfo.processInfo.systemUptime
        lastEnrollmentLogAt = 0
        lastEnrollmentLogState = ""
        status = "Look straight at the camera"
        logger.info("Guided face enrollment started")
        startCamera()
        onNeedsEnrollment?()
    }

    func cancelEnrolment() {
        cancelMacUnlockEnrolmentAuthorization()
        endEnrolment(message: nil)
    }

    func restartEnrolment() {
        guard activity == .watching else { return }
        if isMacUnlockEnrollment, enrollmentOwnerGranted {
            beginEnrolment(name: enrolmentName, forMacUnlock: true)
        } else if isMacUnlockEnrollment {
            startMacUnlockEnrolment(name: enrolmentName)
        } else { startEnrolment(name: enrolmentName) }
    }

    private func endEnrolment(message: String?) {
        logger.info("Guided face enrollment ended: \(message ?? "cancelled", privacy: .public)")
        tracker = nil
        enrollmentAnchor = nil
        enrollmentLastFrame = nil
        enrollmentIsLive = false
        poseCounts = [:]
        activity = .watching
        status = message ?? ""
        onEnrollmentEnded?(message)
        stopCameraIfUnused()
    }

    func finishEnrolment() {
        guard let tracker, canFinishEnrolmentEarly, activity == .enrolling else { return }
        guard var identity = tracker.makeIdentity(name: enrolmentName) else { return }
        let previous = recapturingIdentity
        if let previous { identity.id = previous.id; identity.isEnabled = previous.isEnabled }
        let forMacUnlock = isMacUnlockEnrollment
        let ownerEpoch = enrollmentOwnerEpoch
        self.tracker = nil
        activity = .saving
        status = "Saving your face…"
        Task {
            guard let store = makeStore() else {
                endEnrolment(message: storeProblem ?? "Your face could not be saved. Please try again.")
                return
            }
            do {
                if let previous { try await store.recapture(identity, replacing: previous) }
                else { try await store.upsert(identity) }
                let readable = await refreshIdentities()
                guard !forMacUnlock || enrollmentOwnerEpoch == ownerEpoch else {
                    activity = .watching
                    stopCameraIfUnused()
                    return
                }
                guard readable, identities.contains(identity) else {
                    endEnrolment(message: "Your saved face could not be loaded. Please try again.")
                    return
                }
                activity = .watching
                status = forMacUnlock ? (FaceUnlockModelPolicy.current.unavailableReason
                    ?? "Face saved. Continue with your Mac password.") : "Face saved."
                poseCounts = [:]
                enrollmentIsLive = false
                enrollmentAnchor = nil
                liveActivity.finish(saved: true, recognized: true, message: "Ready for your next check")
                onSaved?(identity)
                stopCameraIfUnused()
                logger.info("Face enrollment saved")
            } catch {
                storeProblem = "Could not save your face: \(error.localizedDescription)"
                endEnrolment(message: "Your face was not saved. Please try again.")
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
                    self.status = self.identities.isEmpty ? "Save your face in the Face tab first."
                        : "Recapture an enabled face in Settings → Face Check to use the current recognition model."
                    self.resolveAuthorization(false)
                    self.onNeedsEnrollment?()
                } else if self.identities.isEmpty {
                    self.resolveAuthorization(true)
                } else {
                    // An incompatible or disabled enrollment is not an empty store.
                    self.status = "Recapture an enabled face in Settings → Face Check to use the current recognition model."
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
        cancelMacUnlockEnrolmentAuthorization()
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
        testOutcome = TestOutcome(matched: matched != nil, name: name, distance: closest?.templateDistance,
                                  limit: matchingDistanceLimit)
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
                    enrollmentIsLive = false
                    enrollmentLastFrame = nil
                    _ = tracker?.noFace()
                    status = "Hold still while the camera catches up."
                    logEnrollmentState("waiting: stale camera frame", at: now)
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
        if let problem = analysis.problem { endEnrolment(message: problem); return }
        if let denial = analysis.liveness?.denial {
            endEnrolment(message: denial.message)
            return
        }
        guard analysis.faceCount == 1, let face = analysis.face, let descriptor = analysis.descriptor,
              analysis.captureGuidance == nil, FaceCaptureFraming.contains(face.bounds),
              analysis.modelIdentifier == enrollmentProfile.identifier,
              enrollmentProfile.prepared(descriptor) != nil, let yaw = face.yaw, let pitch = face.pitch,
              face.quality.isFinite, (0.3...1).contains(face.quality),
              let cues = analysis.liveness, cues.geometry.isUsable, cues.glare.isUsable else {
            enrollmentIsLive = false
            enrollmentLastFrame = nil
            _ = tracker.noFace()
            self.tracker = tracker
            let wait = FaceEnrollmentGuidance.captureWait(for: analysis, profile: enrollmentProfile)
            status = wait.instruction
            logEnrollmentState("waiting: " + wait.reason, at: timestamp)
            return
        }
        if let anchor = enrollmentAnchor, enrollmentProfile.distance(anchor, descriptor) > enrollmentProfile.enrollmentDistance {
            logger.info("Guided capture rejected: primary identity continuity")
            endEnrolment(message: "The face changed. Start a new scan.")
            return
        }
        guard let pad = analysis.pad, pad.capturedAt == timestamp, pad.generation == generation,
              pad.isValid else { endEnrolment(message: "The live-face check is unavailable. Retry the scan."); return }
        let qualification = pad.qualification(minimumLiveScore: FaceModelValidation.bundled?.minimumLiveScore ?? 0.90)
        if qualification == .spoof {
            endEnrolment(message: "A live face could not be verified. Retry in even lighting.")
            return
        }
        guard abs(yaw) <= 25, abs(pitch) <= 25,
              qualification == .live else {
            enrollmentIsLive = false
            enrollmentLastFrame = nil
            _ = tracker.noFace()
            self.tracker = tracker
            if abs(yaw) > 25 || abs(pitch) > 25 {
                status = "Turn your head a little less."
                logEnrollmentState("waiting: head angle beyond capture range", at: timestamp)
            } else {
                status = "Checking for a live face. Hold still in even light."
                logEnrollmentState("waiting: passive models uncertain", at: timestamp)
            }
            return
        }
        if enrollmentAnchor == nil { enrollmentAnchor = descriptor }
        enrollmentIsLive = true
        enrollmentLastFrame = timestamp
        let previousCount = tracker.capturedSampleCount
        // Vision's positive pitch is a downward nod; stored enrollment poses use positive up.
        let event = tracker.process(FaceEnrollmentFrame(yaw: yaw, pitch: -pitch, quality: face.quality, descriptor: descriptor, timestamp: timestamp))
        let instruction = FaceEnrollmentGuidance.instruction(event: event, next: tracker.suggestedPose)
        if tracker.capturedSampleCount != previousCount {
            logger.info("Guided capture accepted: samples=\(tracker.capturedSampleCount) of \(tracker.requiredSampleCount)")
        }
        let expected = tracker.suggestedPose?.rawValue ?? "complete"
        let observed = tracker.rules.bands.pose(yaw: yaw, pitch: -pitch)?.rawValue ?? "between poses"
        // Keep tracker detail in diagnostics without replacing the on-screen direction.
        let captureState: String = switch event {
        case .noFace: "no face"
        case .unusableDescriptor: "unusable input"
        case .betweenPoses: "between poses"
        case .lowQuality: "low quality"
        case .centreFirst: "centre first"
        case .settling: "settling"
        case .wrongPose: "wrong pose"
        case .poseAlreadyCaptured: "completed pose"
        case .holding(_, let progress): "holding " + String(Int(progress * 100)) + "%"
        case .waitingForVariation: "sample spacing"
        case .differentFace: "identity mismatch"
        case .captured: "captured"
        case .complete: "complete"
        }
        logEnrollmentState("expected=" + expected + " observed=" + observed
            + " samples=" + String(tracker.capturedSampleCount) + " state=" + captureState, at: timestamp)
        self.tracker = tracker
        poseCounts = Dictionary(uniqueKeysWithValues: FaceEnrollmentPose.allCases.map { ($0, tracker.capturedCount(for: $0)) })
        status = instruction
        if tracker.isComplete { finishEnrolment() }
    }

    /// Coarse capture states only; no images, measurements, descriptors or identity details.
    private func logEnrollmentState(_ state: String, at timestamp: TimeInterval) {
        guard state != lastEnrollmentLogState || timestamp - lastEnrollmentLogAt >= 2 else { return }
        lastEnrollmentLogState = state
        lastEnrollmentLogAt = timestamp
        logger.debug("Guided capture: \(state, privacy: .public)")
    }

    // MARK: Text

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

#if DEBUG
extension FaceCheckController {
    /// Sets the status line and the last check's result without running the camera or a
    /// check, for screenshots of the Face Check tab. Debug builds only.
    func showcase(status: String, outcome: TestOutcome?) {
        self.status = status
        testOutcome = outcome
    }
}
#endif
