import Foundation

/// Model selection for password entry. Personal testing is an explicit bundle option,
/// separate from release validation; it never creates or changes evaluation evidence.
struct FaceUnlockModelPolicy: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case unavailable, validated, experimental }
    let mode: Mode
    let recognitionProfile: FaceRecognitionProfile?
    let verificationConfiguration: FacePassiveVerificationSession.Configuration

    init(validation: FaceModelValidation?, allowsExperimentalBuild: Bool = false) {
        var configuration = FacePassiveVerificationSession.Configuration.macUnlock
        if let validation, validation.isAccepted {
            mode = .validated
            recognitionProfile = validation.recognitionProfile
            configuration.minimumLiveScore = validation.minimumLiveScore
        } else if allowsExperimentalBuild {
            mode = .experimental
            recognitionProfile = .auraFace
        } else {
            mode = .unavailable
            recognitionProfile = nil
        }
        verificationConfiguration = configuration
    }

    var allowsUnlock: Bool { recognitionProfile != nil }
    var isExperimental: Bool { mode == .experimental }
    var unavailableReason: String? { allowsUnlock ? nil : FaceModelValidation.unavailableMessage }

    static let current = Self(validation: .bundled,
        allowsExperimentalBuild: Bundle.main.object(forInfoDictionaryKey: "NotchyExperimentalFaceUnlock") as? Bool == true)
}
