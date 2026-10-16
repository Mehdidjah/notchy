import SwiftUI

/// The four usage profiles offered on the profile page, in display order.
enum OnboardingProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case developer
    case designer
    case lightUse = "lightuse"
    case student

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: "Developer"
        case .designer: "Designer"
        case .lightUse: "Light Use"
        case .student: "Student"
        }
    }

    var systemImage: String {
        switch self {
        case .developer: "terminal.fill"
        case .designer: "paintbrush.fill"
        case .lightUse: "sparkles"
        case .student: "book.fill"
        }
    }

    var summary: String {
        switch self {
        case .developer:
            "Code and debug with color picker, stats monitoring, and timer."
        case .designer:
            "Create and design with color picker, mirror, and visual effects."
        case .lightUse:
            "Simple and minimal interface with just the essentials for everyday tasks."
        case .student:
            "Stay organized with calendar, timer, and battery monitoring."
        }
    }

    /// Card accent: top-leading to bottom-trailing.
    var gradient: [Color] {
        switch self {
        case .developer: [.blue, .purple]
        case .designer: [.pink, .orange]
        case .lightUse: [.green, .mint]
        case .student: [.indigo, .cyan]
        }
    }
}

/// Which features the island should run, as chosen during onboarding. The host maps these
/// onto its own settings objects through `OnboardingFeature.applyFeatureChoices`.
struct OnboardingFeatureChoices: Equatable, Sendable {
    /// Clipboard history is always on.
    var clipboard = true
    var shelf = true
    var calendar = true
    var mirror = false
    var timer = true
    var stats = false
    var notes = false
    var colorPicker = true
    var lyrics = false
    var inlineHUD = true
    var lightingEffect = true
    var minimalisticUI = false
    var haptics = true
    var menuBarIcon = true

    /// The defaults for every key the profiles touch.
    static let recommendedDefaults = OnboardingFeatureChoices()

    /// Applies the selected profiles on top of `base`:
    /// profiles are applied developer, designer, light use, student, so a later profile wins
    /// where two disagree; clipboard, haptics and the menu bar icon are always switched on and
    /// lyrics always off.
    static func resolved(
        for profiles: Set<OnboardingProfile>,
        base: OnboardingFeatureChoices = .recommendedDefaults
    ) -> OnboardingFeatureChoices {
        var choices = base
        choices.clipboard = true

        if profiles.contains(.developer) {
            choices.colorPicker = true
            choices.stats = true
            choices.timer = true
            choices.mirror = false
            choices.minimalisticUI = false
        }
        if profiles.contains(.designer) {
            choices.colorPicker = true
            choices.mirror = true
            choices.lightingEffect = true
            choices.inlineHUD = true
            choices.stats = false
            choices.timer = false
            choices.minimalisticUI = false
        }
        if profiles.contains(.lightUse) {
            choices.minimalisticUI = true
            choices.colorPicker = false
            choices.mirror = false
            choices.stats = false
            choices.timer = true
            choices.inlineHUD = true
        }
        if profiles.contains(.student) {
            choices.timer = true
            choices.calendar = true
            choices.colorPicker = false
            choices.mirror = false
            choices.stats = false
            choices.minimalisticUI = false
        }
        if !profiles.isEmpty, !profiles.contains(.lightUse) {
            choices.minimalisticUI = false
        }

        choices.menuBarIcon = true
        choices.haptics = true
        choices.lyrics = false
        return choices
    }
}

/// Music sources the island can follow with public APIs (AppleScript over Apple Events).
/// Raw values match the media feature's `MediaSourcePreference`.
///
/// A system "Now Playing" source, and apps that ride on it, would need the private
/// MediaRemote framework. "Automatic" takes the Now Playing card's
/// place: it follows whichever supported app is playing.
enum OnboardingMusicSource: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case appleMusic
    case spotify

    var id: String { rawValue }

    /// Defaults to Apple Music on macOS 15.4 and later.
    static let defaultSource: OnboardingMusicSource = .appleMusic

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    var summary: String {
        switch self {
        case .automatic: "Follows whichever supported app is playing: Apple Music or Spotify."
        case .appleMusic: "Connects directly to the Apple Music app."
        case .spotify: "Connects directly to the Spotify app."
        }
    }

    /// Apps this source talks to.
    var bundleIdentifiers: [String] {
        switch self {
        case .automatic: ["com.apple.Music", "com.spotify.client"]
        case .appleMusic: ["com.apple.Music"]
        case .spotify: ["com.spotify.client"]
        }
    }

    /// Automation permissions this source needs, one per app.
    var automationPermissions: [OnboardingPermission] {
        switch self {
        case .automatic: [.automationMusic, .automationSpotify]
        case .appleMusic: [.automationMusic]
        case .spotify: [.automationSpotify]
        }
    }
}

extension Notification.Name {
    /// Posted after the music page saves a source; `object` is the source's raw value.
    static let onboardingMusicSourceChanged = Notification.Name("onboarding.musicSourceChanged")
}
