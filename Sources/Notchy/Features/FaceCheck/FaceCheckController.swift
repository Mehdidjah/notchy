import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Runs Face Check for the settings page: the camera, the live readouts, enrolment and the test
/// scan. Only results arrive here, a few times a second; every frame is analysed off the main
/// actor by `FaceCheckPipeline`.
@MainActor
final class FaceCheckController: ObservableObject {
    static let shared = FaceCheckController()

    enum CameraState: Equatable {
        case off
        case starting
        case on
        case denied
        case unavailable
    }

    enum Activity: Equatable {
        case watching
        case enrolling
        case testing
    }

    struct TestOutcome: Equatable {
        var matched: Bool
        var name: String?
        /// Closest distance to an enrolled face seen during the scan; nil when no face was seen.
        var distance: Float?
        var limit: Float
    }

    /// How long a test scan looks for a match before giving up.
    static let testDuration: TimeInterval = 3
    private static let presetKey = "faceCheck.matchPreset"

    @Published private(set) var cameraState: CameraState = .off
    @Published private(set) var activity: Activity = .watching
    @Published private(set) var face: FaceFrameObservation?
    @Published private(set) var chip: CGImage?
    /// Distance from the live face to the closest enrolled face.
    @Published private(set) var liveDistance: Float?
    @Published private(set) var status = ""
    @Published private(set) var problem: String?
    @Published private(set) var identities: [FaceIdentity] = []
    @Published private(set) var storeProblem: String?
    @Published private(set) var poseCounts: [FaceEnrollmentPose: Int] = [:]
    @Published private(set) var testOutcome: TestOutcome?
    @Published var preset: FaceMatchPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey)
            rebuildMatcher()
        }
    }

    let camera = FaceCheckCamera()
    private let embedder = FaceEmbedder()
    private lazy var pipeline = FaceCheckPipeline(embedder: embedder)
    private var store: FaceEnrollmentStore?
    private var matcher: FaceMatcher?
    private var tracker: FaceEnrollmentPoseTracker?
    private var enrolmentName = ""
    private var testStarted: Date?
    private var testClosest: FaceMatchScore?
    /// Bumped whenever the camera stops, so a frame still in flight is ignored.
    private var generation = 0

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.presetKey).flatMap(FaceMatchPreset.init(rawValue:))
        preset = saved ?? .standard
    }

    var samplesPerPose: Int { FaceEnrollmentRules.standard.samplesPerPose }
    var canFinishEnrolmentEarly: Bool { (poseCounts[.centre] ?? 0) > 0 }

    // MARK: Camera

    func startCamera() {
        guard cameraState == .off || cameraState == .denied || cameraState == .unavailable else { return }
        cameraState = .starting
        problem = nil
        Task {
            switch FaceCheckCamera.authorization {
            case .authorized:
                break
            case .notDetermined:
                guard await FaceCheckCamera.requestAccess() else {
                    cameraState = .denied
                    return
                }
            default:
                cameraState = .denied
                return
            }
            generation &+= 1
            let current = generation
            let pipeline = pipeline
            camera.start(onFrame: { [weak self] image in
                let analysis = await pipeline.analyze(image)
                await self?.handle(analysis, generation: current)
            }, completion: { [weak self] running in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.cameraState = running ? .on : .unavailable
                    if running { self.status = "Looking for a face…" }
                }
            })
        }
    }

    func stopCamera() {
        generation &+= 1
        camera.stop()
        cameraState = .off
        if activity == .enrolling { cancelEnrolment() }
        if activity == .testing { activity = .watching }
        face = nil
        chip = nil
        liveDistance = nil
        status = ""
        Task { await embedder.unload() }
    }

    // MARK: Store

    func loadIdentities() {
        Task {
            guard let store = makeStore() else { return }
            switch await store.load() {
            case .ready(let loaded):
                identities = loaded
                storeProblem = nil
            case .unreadable(let reason):
                identities = []
                storeProblem = Self.describe(reason)
            case .notLoaded:
                identities = []
            }
            rebuildMatcher()
        }
    }

    func deleteIdentity(_ identity: FaceIdentity) {
        Task {
            guard let store = makeStore() else { return }
            do {
                try await store.removeIdentity(id: identity.id)
                loadIdentities()
            } catch {
                storeProblem = "Could not delete \(identity.name): \(error.localizedDescription)"
            }
        }
    }

    func deleteAllFaceData() {
        Task {
            guard let store = makeStore() else { return }
            do {
                try await store.deleteAll()
                testOutcome = nil
                loadIdentities()
            } catch {
                storeProblem = "Could not delete the face data: \(error.localizedDescription)"
            }
        }
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
        matcher = FaceMatcher(
            identities: identities,
            modelIdentifier: FaceEmbedder.modelIdentifier,
            maximumDistance: preset.maximumDistance
        )
    }

    // MARK: Enrolment

    func startEnrolment(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        enrolmentName = trimmed.isEmpty ? "Me" : trimmed
        tracker = FaceEnrollmentPoseTracker(modelIdentifier: FaceEmbedder.modelIdentifier)
        poseCounts = [:]
        testOutcome = nil
        activity = .enrolling
        status = "Look straight at the camera."
        startCamera()
    }

    func cancelEnrolment() {
        tracker = nil
        poseCounts = [:]
        activity = .watching
        status = cameraState == .on ? "Looking for a face…" : ""
    }

    /// Saves what has been captured so far; needs at least the straight-on pose. A turned pose
    /// that never passes should not trap the user in enrolment.
    func finishEnrolment() {
        guard let tracker else { return }
        let identity = tracker.makeIdentity(name: enrolmentName)
            ?? (canFinishEnrolmentEarly ? FaceIdentity(name: enrolmentName, samples: tracker.samples) : nil)
        guard let identity else { return }
        self.tracker = nil
        activity = .watching
        status = "Saving \(identity.name)…"
        Task {
            guard let store = makeStore() else { return }
            do {
                try await store.upsert(identity)
                status = "Saved \(identity.name) (\(identity.samples.count) samples). Try the test."
                poseCounts = [:]
                loadIdentities()
            } catch {
                storeProblem = "Could not save \(identity.name): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Test

    func startTest() {
        guard matcher?.hasComparableIdentities == true else {
            status = "Enrol a face first."
            return
        }
        testOutcome = nil
        testClosest = nil
        testStarted = Date()
        activity = .testing
        status = "Look at the camera…"
        startCamera()
    }

    private func finishTest(matched: FaceMatchScore?) {
        let closest = matched ?? testClosest
        let name = closest.flatMap { score in identities.first { $0.id == score.identityID }?.name }
        let outcome = TestOutcome(
            matched: matched != nil,
            name: matched != nil ? name : nil,
            distance: closest?.templateDistance,
            limit: preset.maximumDistance
        )
        testOutcome = outcome
        activity = .watching
        testStarted = nil
        status = outcome.matched ? "It's \(name ?? "you")." : "Not recognized."
        IslandActivityCenter.shared.requestSneakPeek(SneakPeek(
            kind: .generic,
            systemImage: outcome.matched ? "faceid" : "person.crop.circle.badge.xmark",
            title: outcome.matched ? "It's you" : "Face not recognized",
            subtitle: outcome.matched ? name : nil,
            tint: outcome.matched ? .green : .orange,
            duration: .seconds(2)
        ))
    }

    // MARK: Frames

    private func handle(_ analysis: FaceFrameAnalysis, generation frameGeneration: Int) {
        guard frameGeneration == generation, cameraState == .on || cameraState == .starting else { return }
        face = analysis.face
        if let chip = analysis.chip { self.chip = chip }
        problem = analysis.problem

        var bestScore: FaceMatchScore?
        if let descriptor = analysis.descriptor, let matcher {
            let result = matcher.match(descriptor)
            bestScore = result.scores.min { $0.templateDistance < $1.templateDistance }
            liveDistance = bestScore?.templateDistance
        } else if analysis.face == nil {
            liveDistance = nil
        }

        switch activity {
        case .watching:
            if analysis.face == nil { status = "Looking for a face…" }
            else if analysis.descriptor != nil, status.hasPrefix("Looking") { status = "Face found." }
        case .enrolling:
            feedEnrolment(analysis)
        case .testing:
            feedTest(analysis, best: bestScore)
        }
    }

    private func feedEnrolment(_ analysis: FaceFrameAnalysis) {
        guard var tracker else { return }
        let event: FaceEnrollmentEvent
        if let face = analysis.face, let descriptor = analysis.descriptor, let yaw = face.yaw, let pitch = face.pitch {
            event = tracker.process(FaceEnrollmentFrame(
                yaw: yaw,
                pitch: pitch,
                quality: face.quality,
                descriptor: descriptor,
                timestamp: ProcessInfo.processInfo.systemUptime
            ))
        } else {
            event = tracker.noFace()
        }
        self.tracker = tracker
        poseCounts = Dictionary(uniqueKeysWithValues: FaceEnrollmentPose.allCases.map { ($0, tracker.capturedCount(for: $0)) })
        status = Self.describe(event, next: tracker.suggestedPose)
        if tracker.isComplete { finishEnrolment() }
    }

    private func feedTest(_ analysis: FaceFrameAnalysis, best: FaceMatchScore?) {
        if let best, testClosest == nil || best.templateDistance < testClosest!.templateDistance {
            testClosest = best
        }
        if let descriptor = analysis.descriptor, let matcher,
           case .matched(let score) = matcher.match(descriptor).decision {
            finishTest(matched: score)
            return
        }
        if let testStarted, Date().timeIntervalSince(testStarted) >= Self.testDuration {
            finishTest(matched: nil)
        }
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
