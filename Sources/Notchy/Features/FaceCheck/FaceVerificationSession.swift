import Foundation

/// Single-use completion, detached before invocation so reentrant UI actions cannot replay it.
@MainActor
final class FaceAuthorizationRequest {
    private var completion: (@MainActor (Bool) -> Void)?
    var isResolved: Bool { completion == nil }
    init(completion: @escaping @MainActor (Bool) -> Void) { self.completion = completion }
    func resolve(_ allowed: Bool) {
        let callback = completion
        completion = nil
        callback?(allowed)
    }
}

/// Identity continuity and liveness must belong to the same fresh sequence of frames.
struct FaceVerificationSession {
    enum Result: Equatable { case waiting(String), recognized(FaceMatchScore), rejected(String) }
    let matcher: FaceMatcher
    private var liveness: FaceLivenessTracker
    private var identityID: UUID?
    private var matchingFrames = 0
    private var firstMatch: TimeInterval?
    private var lastFrame: TimeInterval?
    private var terminal: Result?
    private(set) var closest: FaceMatchScore?

    init(matcher: FaceMatcher, direction: FaceLivenessDirection) {
        self.matcher = matcher
        liveness = FaceLivenessTracker(direction: direction)
    }

    mutating func consume(_ analysis: FaceFrameAnalysis, timestamp: TimeInterval) -> Result {
        if let terminal { return terminal }
        guard timestamp.isFinite, lastFrame.map({ timestamp > $0 }) ?? true else {
            return finish(.rejected("The camera frames were out of order. Retry the check."))
        }
        let gap = lastFrame.map { timestamp - $0 > 1 } ?? false
        lastFrame = timestamp
        if let denial = analysis.liveness?.denial { return finish(.rejected(denial.message)) }
        if let problem = analysis.problem { return finish(.rejected(problem)) }
        if analysis.descriptor != nil, analysis.modelIdentifier != matcher.modelIdentifier {
            return finish(.rejected("The face model changed. Retry the check."))
        }
        if let guidance = analysis.captureGuidance {
            reset(timestamp: timestamp)
            return .waiting(guidance)
        }
        guard analysis.faceCount == 1, let face = analysis.face, face.quality >= 0.3,
              FaceCaptureFraming.contains(face.bounds),
              let descriptor = analysis.descriptor,
              case .matched(let score) = matcher.match(descriptor).decision else {
            reset(timestamp: timestamp)
            return .waiting(analysis.faceCount > 1 ? "Only one person should be in view." : "Look at the camera in good light.")
        }
        if closest == nil || score.templateDistance < closest!.templateDistance { closest = score }
        if gap || (identityID != nil && identityID != score.identityID) { reset(timestamp: timestamp - 0.000_001) }
        identityID = score.identityID
        if firstMatch == nil { firstMatch = timestamp }
        matchingFrames += 1
        switch liveness.consume(analysis.liveness, timestamp: timestamp) {
        case .collecting(let prompt): return .waiting(prompt.message)
        case .rejected(let failure): return finish(.rejected(failure.message))
        case .passed:
            guard matchingFrames >= 3, timestamp - (firstMatch ?? timestamp) >= 0.35 else {
                return .waiting("Hold still for a moment.")
            }
            return finish(.recognized(score))
        }
    }

    private mutating func reset(timestamp: TimeInterval) {
        _ = liveness.consume(nil, timestamp: timestamp)
        matchingFrames = 0
        firstMatch = nil
        identityID = nil
    }
    private mutating func finish(_ result: Result) -> Result { terminal = result; return result }
}
