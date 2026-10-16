import Combine
import Foundation

/// Camera and microphone indicator preferences, stored under `privacy.*` keys in UserDefaults.
/// Both default to on, as in Atoll.
@MainActor
final class PrivacySettings: ObservableObject {
    enum Key {
        static let enableCameraDetection = "privacy.enableCameraDetection"
        static let enableMicrophoneDetection = "privacy.enableMicrophoneDetection"
    }

    static let shared = PrivacySettings()

    private let defaults: UserDefaults

    /// Show the green camera glyph while any app has a camera running.
    @Published var enableCameraDetection: Bool {
        didSet { defaults.set(enableCameraDetection, forKey: Key.enableCameraDetection) }
    }

    /// Show the orange microphone glyph while any app is capturing audio input.
    @Published var enableMicrophoneDetection: Bool {
        didSet { defaults.set(enableMicrophoneDetection, forKey: Key.enableMicrophoneDetection) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enableCameraDetection = defaults.object(forKey: Key.enableCameraDetection) as? Bool ?? true
        enableMicrophoneDetection = defaults.object(forKey: Key.enableMicrophoneDetection) as? Bool ?? true
    }

    /// The live activity is only offered while at least one detector is switched on.
    var anyDetectionEnabled: Bool { enableCameraDetection || enableMicrophoneDetection }
}
