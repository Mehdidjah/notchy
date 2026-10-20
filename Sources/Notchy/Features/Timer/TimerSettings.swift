import Combine
import Foundation
import SwiftUI

/// How the running timer draws its progress.
enum TimerProgressStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case bar
    case ring

    var id: Self { self }

    var label: String {
        switch self {
        case .bar: "Bar"
        case .ring: "Ring"
        }
    }
}

/// Where the timer glyph and progress take their colour from.
enum TimerIconColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The preset's colour, or the green-to-red ramp for custom timers.
    case adaptive
    /// One fixed colour for every timer.
    case solid

    var id: Self { self }

    var label: String {
        switch self {
        case .adaptive: "Adaptive"
        case .solid: "Solid"
        }
    }
}

/// Timer preferences, stored under "timer." keys in UserDefaults.
@MainActor
final class TimerSettings: ObservableObject {
    static let shared = TimerSettings()

    enum Key {
        static let presets = "timer.presets"
        static let soundEnabled = "timer.soundEnabled"
        static let soundName = "timer.soundName"
        static let notificationsEnabled = "timer.notificationsEnabled"
        static let liveActivityEnabled = "timer.liveActivityEnabled"
        static let inlineControlsEnabled = "timer.inlineControlsEnabled"
        static let showsCountdown = "timer.showsCountdown"
        static let showsLabel = "timer.showsLabel"
        static let showsProgress = "timer.showsProgress"
        static let progressStyle = "timer.progressStyle"
        static let iconColorMode = "timer.iconColorMode"
        static let solidColor = "timer.solidColor"
        static let showsPresetsInTab = "timer.showsPresetsInTab"
        static let customDuration = "timer.customDuration"
        static let tabMode = "timer.tabMode"
    }

    /// System alert sounds that ship with macOS and can be played by name.
    static let availableSounds = [
        "Glass", "Blow", "Bottle", "Frog", "Funk", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
    static let defaultSoundName = "Glass"
    static let defaultCustomDuration: TimeInterval = 600

    private let defaults: UserDefaults

    @Published var presets: [TimerPreset] {
        didSet { Self.store(presets: presets, in: defaults) }
    }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var soundName: String { didSet { defaults.set(soundName, forKey: Key.soundName) } }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    /// Whether a running timer shows on the closed notch at all.
    @Published var liveActivityEnabled: Bool {
        didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivityEnabled) }
    }
    /// Pause and stop buttons on the closed notch.
    @Published var inlineControlsEnabled: Bool {
        didSet { defaults.set(inlineControlsEnabled, forKey: Key.inlineControlsEnabled) }
    }
    @Published var showsCountdown: Bool { didSet { defaults.set(showsCountdown, forKey: Key.showsCountdown) } }
    @Published var showsLabel: Bool { didSet { defaults.set(showsLabel, forKey: Key.showsLabel) } }
    @Published var showsProgress: Bool { didSet { defaults.set(showsProgress, forKey: Key.showsProgress) } }
    @Published var progressStyle: TimerProgressStyle {
        didSet { defaults.set(progressStyle.rawValue, forKey: Key.progressStyle) }
    }
    @Published var iconColorMode: TimerIconColorMode {
        didSet { defaults.set(iconColorMode.rawValue, forKey: Key.iconColorMode) }
    }
    @Published var solidColor: TimerColorComponents {
        didSet { defaults.set(try? JSONEncoder().encode(solidColor), forKey: Key.solidColor) }
    }
    @Published var showsPresetsInTab: Bool {
        didSet { defaults.set(showsPresetsInTab, forKey: Key.showsPresetsInTab) }
    }
    /// The last duration typed into the custom composer, so the fields come back as left.
    @Published var customDuration: TimeInterval {
        didSet { defaults.set(customDuration, forKey: Key.customDuration) }
    }
    /// The mode the Timer tab shows while no timer runs.
    @Published var tabMode: TimerTabMode {
        didSet { defaults.set(tabMode.rawValue, forKey: Key.tabMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = Self.loadPresets(from: defaults)
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        let storedSound = defaults.string(forKey: Key.soundName) ?? Self.defaultSoundName
        soundName = Self.availableSounds.contains(storedSound) ? storedSound : Self.defaultSoundName
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        liveActivityEnabled = defaults.object(forKey: Key.liveActivityEnabled) as? Bool ?? true
        inlineControlsEnabled = defaults.object(forKey: Key.inlineControlsEnabled) as? Bool ?? true
        showsCountdown = defaults.object(forKey: Key.showsCountdown) as? Bool ?? true
        showsLabel = defaults.object(forKey: Key.showsLabel) as? Bool ?? false
        showsProgress = defaults.object(forKey: Key.showsProgress) as? Bool ?? true
        progressStyle = TimerProgressStyle(rawValue: defaults.string(forKey: Key.progressStyle) ?? "") ?? .bar
        iconColorMode = TimerIconColorMode(rawValue: defaults.string(forKey: Key.iconColorMode) ?? "") ?? .adaptive
        solidColor = (defaults.data(forKey: Key.solidColor)).flatMap {
            try? JSONDecoder().decode(TimerColorComponents.self, from: $0)
        } ?? .systemBlue
        showsPresetsInTab = defaults.object(forKey: Key.showsPresetsInTab) as? Bool ?? true
        customDuration = max(0, defaults.object(forKey: Key.customDuration) as? Double ?? Self.defaultCustomDuration)
        tabMode = TimerTabMode(rawValue: defaults.string(forKey: Key.tabMode) ?? "") ?? .focus
    }

    func preset(withID id: UUID?) -> TimerPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    func addPreset() {
        let colors: [TimerColorComponents] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple]
        let color = colors[presets.count % colors.count]
        presets.append(TimerPreset(name: "Timer \(presets.count + 1)", duration: 10 * 60, colorComponents: color))
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func restoreDefaultPresets() {
        presets = TimerPreset.defaultPresets
    }

    /// True when the presets read as the defaults, whatever identifiers they carry.
    var presetsMatchDefaults: Bool {
        let defaults = TimerPreset.defaultPresets
        guard presets.count == defaults.count else { return false }
        return zip(presets, defaults).allSatisfy { lhs, rhs in
            lhs.name == rhs.name && lhs.duration == rhs.duration && lhs.colorComponents == rhs.colorComponents
        }
    }

    // MARK: - Persistence

    /// Presets are encoded as JSON. A missing or unreadable value yields the defaults;
    /// an explicitly empty list stays empty.
    static func loadPresets(from defaults: UserDefaults) -> [TimerPreset] {
        guard let data = defaults.data(forKey: Key.presets) else { return TimerPreset.defaultPresets }
        guard let decoded = try? JSONDecoder().decode([TimerPreset].self, from: data) else {
            return TimerPreset.defaultPresets
        }
        return decoded
    }

    static func store(presets: [TimerPreset], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Key.presets)
    }
}
