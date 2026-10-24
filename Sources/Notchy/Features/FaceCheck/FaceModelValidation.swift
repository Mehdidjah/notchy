import Foundation

/// A release artifact made by the offline evaluation tool, never a user preference or bypass flag.
/// Normal builds require complete evidence. Explicit personal testing is a separate model policy.
struct FaceModelValidation: Codable, Equatable, Sendable {
    struct Attack: Codable, Equatable, Sendable { var attempts: Int; var accepted: Int }
    var schemaVersion: Int
    var recognitionIdentifier: String
    var recognitionSourceSHA256: String
    var padIdentifier: String
    var capturePolicyVersion: Int
    var calibrationSessionIDs: [String]
    var evaluationSessionIDs: [String]
    var strictCosineDistance: Float
    var minimumLiveScore: Float
    var minimumRecognitionParity: Double
    var maximumPADProbabilityError: Double
    var pipelineP95Milliseconds: Double
    var genuineAttempts: Int
    var genuineAccepted: Int
    var impostorAttempts: Int
    var recognitionGenuineFrames: Int
    var recognitionImpostorFrames: Int
    var baselineFalseAccepts: Int
    var candidateFalseAccepts: Int
    var baselineFalseRejects: Int
    var candidateFalseRejects: Int
    var attacks: [String: Attack]

    var isAccepted: Bool {
        guard schemaVersion == 1, recognitionIdentifier == FaceRecognitionProfile.auraFace.identifier,
              recognitionSourceSHA256 == FaceRecognitionProfile.auraFace.sourceSHA256,
              padIdentifier == FacePADModel.modelIdentifier, capturePolicyVersion == 2,
              !calibrationSessionIDs.isEmpty, !evaluationSessionIDs.isEmpty,
              (calibrationSessionIDs + evaluationSessionIDs).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(calibrationSessionIDs).isDisjoint(with: Set(evaluationSessionIDs)),
              strictCosineDistance.isFinite, (0.01...0.4).contains(strictCosineDistance),
              minimumLiveScore.isFinite, (0.90...0.99).contains(minimumLiveScore),
              minimumRecognitionParity.isFinite, minimumRecognitionParity >= 0.99999, minimumRecognitionParity <= 1.000001,
              maximumPADProbabilityError.isFinite, (0...0.001).contains(maximumPADProbabilityError),
              pipelineP95Milliseconds.isFinite, pipelineP95Milliseconds > 0, pipelineP95Milliseconds <= 200,
              genuineAttempts >= 100, genuineAccepted >= 0, genuineAccepted <= genuineAttempts,
              Double(genuineAccepted) / Double(genuineAttempts) >= 0.95,
              impostorAttempts >= 100, recognitionGenuineFrames >= 100, recognitionImpostorFrames >= 100,
              baselineFalseAccepts >= 0, baselineFalseAccepts <= recognitionImpostorFrames,
              candidateFalseAccepts == 0, candidateFalseAccepts <= baselineFalseAccepts,
              baselineFalseRejects > candidateFalseRejects, baselineFalseRejects <= recognitionGenuineFrames,
              candidateFalseRejects >= 0
        else { return false }
        return ["printed-photo", "screen-photo", "replay-video"].allSatisfy {
            guard let result = attacks[$0] else { return false }
            return result.attempts >= 100 && result.accepted == 0
        }
    }

    var recognitionProfile: FaceRecognitionProfile {
        FaceRecognitionProfile.auraFace.withStrictDistance(strictCosineDistance)
    }

    static let unavailableMessage = "Automatic Face Unlock is awaiting live-camera validation in this build. Use your Mac password for now."

    static let bundled: Self? = {
        guard let url = Bundle.main.url(forResource: "FaceValidation", withExtension: "json"),
              let data = try? Data(contentsOf: url), let report = try? JSONDecoder().decode(Self.self, from: data),
              report.isAccepted else { return nil }
        return report
    }()

    static var activeProfile: FaceRecognitionProfile { bundled?.recognitionProfile ?? .auraFace }
}
