import AppKit

/// Entry point for onboarding: the notch hello with its welcome chime at first launch, and the
/// onboarding window, which opens only when asked for with `showOnboardingAgain()`.
///
/// The host wires the hooks before calling `start()`:
/// - `openIsland` / `closeIsland` open the island held open for the hello and close it again;
///   `openIsland` returns false when the island cannot open;
/// - `openSettings` opens the Settings window ("Customize in Settings");
/// - `currentFeatureChoices` / `applyFeatureChoices` read and write the feature switches;
/// - `currentMusicSource` / `applyMusicSource` read and save the music source;
/// - `applyFocusDetectionMode` saves the answer to the "Focus detection mode" question the
///   window asks when it opens (a confirmation dialog). Leave it nil to skip the question.
@MainActor
enum OnboardingFeature {
    static var openIsland: (() -> Bool)?
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
        let isFirstLaunch = !settings.helloShown
        var chimePending = isFirstLaunch && settings.playsWelcomeSound
        hello.openIsland = {
            guard OnboardingFeature.openIsland?() == true else { return false }
            if chimePending {
                chimePending = false
                OnboardingWelcomeSound.play()
            }
            return true
        }
        hello.closeIsland = { OnboardingFeature.closeIsland?() }
        hello.onFinished = { OnboardingSettings.shared.helloShown = true }

        if isFirstLaunch {
            hello.present()
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

/// The two answers to the "Focus detection mode" question.
enum OnboardingFocusDetectionMode: String, CaseIterable, Sendable {
    /// Also read Focus names from the unified log ("Use DevTools").
    case useDevTools
    /// Rely on the system's Focus notifications only ("Use without DevTools").
    case withoutDevTools

    var title: String {
        switch self {
        case .useDevTools: "Use DevTools"
        case .withoutDevTools: "Use without DevTools"
        }
    }
}

/// The welcome chime played with the first-launch hello. Notchy ships no audio assets, so it
/// uses the system "Hero" sound.
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
