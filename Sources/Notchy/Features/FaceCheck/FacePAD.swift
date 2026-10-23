import Foundation

enum FacePADQualification: Equatable, Sendable {
    case live
    case uncertain
    case spoof
    case invalid
}

/// Independent presentation-attack evidence from the exact frame used for identity matching.
/// Scores are model outputs, not probabilities that a person is safe to authenticate.
struct FacePADObservation: Equatable, Sendable {
    static let modelIdentifier = "minifasnet-v2-v1se-b6d5f04-fp32-v1"

    var modelIdentifier: String = Self.modelIdentifier
    var capturedAt: TimeInterval
    var generation: Int
    var miniFASNetV2: [Float]
    var miniFASNetV1SE: [Float]

    var isValid: Bool {
        modelIdentifier == Self.modelIdentifier && capturedAt.isFinite && capturedAt >= 0 &&
        Self.validProbabilities(miniFASNetV2) && Self.validProbabilities(miniFASNetV1SE)
    }

    /// Requiring agreement prevents one model from averaging away the other's uncertainty.
    func qualification(minimumLiveScore: Float = 0.90) -> FacePADQualification {
        guard isValid, minimumLiveScore.isFinite, (0.90...1).contains(minimumLiveScore) else { return .invalid }
        if [miniFASNetV2, miniFASNetV1SE].contains(where: {
            max($0[0], $0[2]) >= minimumLiveScore
        }) { return .spoof }
        return [miniFASNetV2, miniFASNetV1SE].allSatisfy { scores in
            scores[1] >= minimumLiveScore && scores[1] > scores[0] && scores[1] > scores[2]
        } ? .live : .uncertain
    }

    private static func validProbabilities(_ values: [Float]) -> Bool {
        values.count == 3 && values.allSatisfy { $0.isFinite && (0...1).contains($0) } &&
        abs(values.reduce(0, +) - 1) <= 0.001
    }
}
