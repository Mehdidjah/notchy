import Combine
import Foundation

/// Onboarding preferences, stored under "onboarding." keys in UserDefaults.
///
/// Two flags: `completed` is set when the user reaches the last page of the onboarding
/// window, and `helloShown` once the first-launch "hello" has played in the notch, so the
/// hello plays exactly once.
@MainActor
final class OnboardingSettings: ObservableObject {
    static let shared = OnboardingSettings()

    enum Key {
        static let completed = "onboarding.completed"
        static let completedAt = "onboarding.completedAt"
        static let helloShown = "onboarding.helloShown"
        static let playsWelcomeSound = "onboarding.playsWelcomeSound"
        static let selectedProfiles = "onboarding.selectedProfiles"
        static let musicSource = "onboarding.musicSource"
    }

    /// The user reached the final page and pressed Finish or Customize in Settings.
    @Published var completed: Bool {
        didSet { defaults.set(completed, forKey: Key.completed) }
    }

    /// When the onboarding was last completed.
    @Published private(set) var completedAt: Date? {
        didSet { defaults.set(completedAt, forKey: Key.completedAt) }
    }

    /// The first-launch hello has played in the notch.
    @Published var helloShown: Bool {
        didSet { defaults.set(helloShown, forKey: Key.helloShown) }
    }

    /// Plays the welcome chime together with the first-launch hello.
    @Published var playsWelcomeSound: Bool {
        didSet { defaults.set(playsWelcomeSound, forKey: Key.playsWelcomeSound) }
    }

    /// Profiles picked on the profile page, remembered so a repeat run starts from them.
    @Published var selectedProfiles: Set<OnboardingProfile> {
        didSet { defaults.set(selectedProfiles.map(\.rawValue).sorted(), forKey: Key.selectedProfiles) }
    }

    /// Music app picked on the music page.
    @Published var musicSource: OnboardingMusicSource {
        didSet { defaults.set(musicSource.rawValue, forKey: Key.musicSource) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completed = defaults.object(forKey: Key.completed) as? Bool ?? false
        completedAt = defaults.object(forKey: Key.completedAt) as? Date
        helloShown = defaults.object(forKey: Key.helloShown) as? Bool ?? false
        playsWelcomeSound = defaults.object(forKey: Key.playsWelcomeSound) as? Bool ?? true
        let storedProfiles = defaults.stringArray(forKey: Key.selectedProfiles) ?? []
        selectedProfiles = Set(storedProfiles.compactMap(OnboardingProfile.init(rawValue:)))
        musicSource = (defaults.string(forKey: Key.musicSource))
            .flatMap(OnboardingMusicSource.init(rawValue:)) ?? .defaultSource
    }

    /// The user has not reached the last page of the onboarding window yet.
    var needsOnboarding: Bool { !completed }

    func markCompleted(at date: Date = Date()) {
        completedAt = date
        completed = true
    }

    /// Forgets that onboarding ran: the hello plays again at the next launch and the window
    /// counts as not finished.
    func resetForNextLaunch() {
        completed = false
        completedAt = nil
        helloShown = false
    }
}
