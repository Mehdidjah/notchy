import AppKit

/// Entry point for onboarding: the first-launch window, the welcome chime and the notch hello.
///
/// The host wires the hooks before calling `start()`:
/// - `openIsland` / `closeIsland` open the island held open for the hello and close it again;
/// - `openSettings` opens the Settings window ("Customize in Settings");
/// - `currentFeatureChoices` / `applyFeatureChoices` read and write the feature switches;
/// - `currentMusicSource` / `applyMusicSource` read and save the music source;
/// - `applyFocusDetectionMode` saves the answer to the "Focus detection mode" question the
///   window asks when it opens (Atoll's confirmation dialog). Leave it nil to skip the question.
@MainActor
enum OnboardingFeature {
    static var openIsland: (() -> Void)?
    static var closeIsland: (() -> Void)?
    static var openSettings: (() -> Void)?
    static var currentFeatureChoices: (() -> OnboardingFeatureChoices)?
    static var applyFeatureChoices: ((OnboardingFeatureChoices) -> Void)?
    static var currentMusicSource: (() -> OnboardingMusicSource)?
    static var applyMusicSource: ((OnboardingMusicSource) -> Void)?
    static var applyFocusDetectionMode: ((OnboardingFocusDetectionMode) -> Void)?

    private(set) static var isRunning = false

    static func start() {
        guard !isRunning else { return }
        isRunning = true

        let settings = OnboardingSettings.shared
        let hello = OnboardingHelloController.shared
        hello.openIsland = { OnboardingFeature.openIsland?() }
        hello.closeIsland = { OnboardingFeature.closeIsland?() }
        hello.onFinished = { OnboardingSettings.shared.helloShown = true }

        let isFirstLaunch = !settings.helloShown
        if isFirstLaunch {
            hello.present()
        }
        if settings.needsOnboarding {
            // Next turn of the run loop, after the island window exists (Atoll: main.async).
            Task { @MainActor in OnboardingWindowController.showIfNeeded() }
        }
        if isFirstLaunch, settings.playsWelcomeSound {
            OnboardingWelcomeSound.play()
        }
    }

    static func stop() {
        guard isRunning else { return }
        isRunning = false
        OnboardingHelloController.shared.cancel()
        OnboardingPermissionCenter.shared.stopMonitoring()
        OnboardingWelcomeSound.stop()
    }

    /// Opens the onboarding window again from Settings.
    static func showOnboardingAgain() {
        OnboardingWindowController.shared.show()
    }

    /// Plays the notch hello again.
    static func replayHello() {
        OnboardingHelloController.shared.replay()
    }
}

/// The two answers to Atoll's "Focus detection mode" question.
enum OnboardingFocusDetectionMode: String, CaseIterable, Sendable {
    /// Also read Focus names from the unified log (Atoll: "Use DevTools").
    case useDevTools
    /// Rely on the system's Focus notifications only (Atoll: "Use without DevTools").
    case withoutDevTools

    var title: String {
        switch self {
        case .useDevTools: "Use DevTools"
        case .withoutDevTools: "Use without DevTools"
        }
    }
}

/// The welcome chime played with the first-launch hello. Atoll plays a bundled clip; NotchIsland
/// ships no audio assets, so it uses the system "Hero" sound.
@MainActor
enum OnboardingWelcomeSound {
    static let soundName = NSSound.Name("Hero")
    private static var sound: NSSound?

    static func play() {
        guard let sound = NSSound(named: soundName)?.copy() as? NSSound else { return }
        sound.volume = 0.6
        Self.sound = sound
        sound.play()
    }

    static func stop() {
        sound?.stop()
        sound = nil
    }
}
