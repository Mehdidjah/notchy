import Foundation

/// A passive policy is deliberately separate from the prompted in-app liveness challenge.
/// Every qualifying frame must independently match the same identity and pass both PAD models.
struct FacePassiveVerificationSession {
    typealias Result = FaceVerificationSession.Result

    struct Configuration: Equatable, Sendable {
        var minimumSamples = 8
        var minimumSpan: TimeInterval = 1.2
        var minimumSampleSpacing: TimeInterval = 0.1
        var maximumGap: TimeInterval = 0.5
        var minimumQuality = 0.3
        var maximumPose = 25.0
        var minimumLiveScore: Float = 0.90
        var requiresMotion = false
        var minimumFaceWidth = 0.0

        static let macUnlock = Self()

        // Policy customization may tighten the defaults, but cannot silently weaken them.
        var isValid: Bool {
            minimumSamples >= 8 && minimumSpan.isFinite && minimumSpan >= 1.2 &&
            minimumSampleSpacing.isFinite && minimumSampleSpacing >= 0.1 &&
            maximumGap.isFinite && maximumGap > minimumSampleSpacing && maximumGap <= 0.5 &&
            minimumQuality.isFinite && (0.3...1).contains(minimumQuality) &&
            maximumPose.isFinite && maximumPose > 0 && maximumPose <= 25 &&
            minimumFaceWidth.isFinite && (0...0.5).contains(minimumFaceWidth) &&
            minimumLiveScore.isFinite && (0.90...1).contains(minimumLiveScore)
        }
    }

    let matcher: FaceMatcher
    let generation: Int
    let configuration: Configuration
    private var lastFrame: TimeInterval?
    private var lastSample: TimeInterval?
    private var firstSample: TimeInterval?
    private var identityID: UUID?
    private(set) var matchingSamples = 0
    private(set) var closest: FaceMatchScore?
    private var terminal: Result?
    private var motion = FaceLivenessTracker(direction: .left, requiresBlinkAndTurn: false)

    init(matcher: FaceMatcher, generation: Int = 0, configuration: Configuration = .macUnlock) {
        self.matcher = matcher
        self.generation = generation
        self.configuration = configuration
    }

    mutating func consume(_ analysis: FaceFrameAnalysis, timestamp: TimeInterval) -> Result {
        if let terminal { return terminal }
        guard configuration.isValid, timestamp.isFinite, timestamp >= 0,
              analysis.capturedAt == timestamp, lastFrame.map({ timestamp > $0 }) ?? true else {
            return finish(.rejected("The camera frames were interrupted. Please retry."))
        }
        if let lastFrame, timestamp - lastFrame > configuration.maximumGap { reset() }
        lastFrame = timestamp

        // A visible screen or reflection cannot be bypassed by missing identity/PAD output.
        if let denial = analysis.liveness?.denial { return finish(.rejected(denial.message)) }
        if let problem = analysis.problem { return finish(.rejected(problem)) }
        if let guidance = analysis.captureGuidance {
            reset()
            return .waiting(guidance)
        }
        guard analysis.faceCount == 1, let face = analysis.face else {
            reset()
            return .waiting(analysis.faceCount > 1 ? "Keep only your face in view." : "Look at the camera.")
        }
        guard FaceCaptureFraming.contains(face.bounds) else {
            reset()
            return .waiting(FaceCaptureFraming.guidance)
        }
        guard face.bounds.width >= configuration.minimumFaceWidth else {
            reset()
            return .waiting("Move closer to the camera.")
        }
        guard face.quality.isFinite, (configuration.minimumQuality...1).contains(face.quality),
              let yaw = face.yaw, let pitch = face.pitch, yaw.isFinite, pitch.isFinite,
              abs(yaw) <= configuration.maximumPose, abs(pitch) <= configuration.maximumPose,
              let cues = analysis.liveness, cues.geometry.isUsable, cues.glare.isUsable,
              let descriptor = analysis.descriptor else {
            reset()
            return .waiting("Look at the camera in even lighting.")
        }
        guard analysis.modelIdentifier == matcher.modelIdentifier else {
            return finish(.rejected("The recognition model changed. Enter your password."))
        }
        guard let pad = analysis.pad, pad.isValid, pad.capturedAt == timestamp, pad.generation == generation else {
            return finish(.rejected("The face safety check is unavailable. Enter your password."))
        }
        switch pad.qualification(minimumLiveScore: configuration.minimumLiveScore) {
        case .invalid:
            return finish(.rejected("The face safety check failed. Enter your password."))
        case .spoof:
            return finish(.rejected("A live face could not be verified. Enter your password."))
        case .uncertain:
            reset()
            return .waiting("Look at the camera in even lighting.")
        case .live:
            break
        }
        guard case .matched(let score) = matcher.match(descriptor).decision else {
            reset()
            return .waiting("Look at the camera.")
        }
        if closest == nil || score.templateDistance < closest!.templateDistance { closest = score }
        if let identityID, identityID != score.identityID { reset() }
        identityID = score.identityID

        if configuration.requiresMotion {
            switch motion.consume(analysis.liveness, timestamp: timestamp) {
            case .collecting(let prompt):
                return .waiting(prompt == .blink ? "Blink once or slowly turn your head." : prompt.message)
            case .rejected(let failure): return finish(.rejected(failure.message))
            case .passed: break
            }
        }

        // Validate every observed frame above, including frames too close together to count.
        if let lastSample, timestamp - lastSample + 1e-9 < configuration.minimumSampleSpacing {
            return .waiting("Checking your face…")
        }
        if firstSample == nil { firstSample = timestamp }
        lastSample = timestamp
        matchingSamples += 1
        guard matchingSamples >= configuration.minimumSamples,
              timestamp - (firstSample ?? timestamp) + 1e-9 >= configuration.minimumSpan else {
            return .waiting("Checking your face…")
        }
        return finish(.recognized(score))
    }

    private mutating func reset() {
        firstSample = nil
        lastSample = nil
        identityID = nil
        matchingSamples = 0
        motion = FaceLivenessTracker(direction: .left, requiresBlinkAndTurn: false)
    }

    private mutating func finish(_ result: Result) -> Result {
        terminal = result
        return result
    }
}
