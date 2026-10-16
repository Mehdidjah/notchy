import Combine
import SwiftUI

/// How a volume or microphone change is drawn on the closed notch.
enum SystemHUDStyle: String, CaseIterable, Identifiable, Sendable {
    /// "Default": a row of icon, level bar and percentage that drops under the notch.
    case standard
    /// "Inline" (the default): the notch grows sideways, icon and label on the left,
    /// level bar on the right.
    case inline

    var id: Self { self }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .inline: "Inline"
        }
    }
}

/// Fill of the level bar.
enum SystemHUDProgressBarStyle: String, CaseIterable, Identifiable, Sendable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"

    var id: Self { self }
    var displayName: String { rawValue }
}

/// Colour of the Caps Lock glyph and label.
enum CapsLockTintMode: String, CaseIterable, Identifiable, Sendable {
    case green
    case accent
    case white

    var id: Self { self }

    var displayName: String {
        switch self {
        case .green: "Green"
        case .accent: "Accent"
        case .white: "White"
        }
    }

    var color: Color {
        switch self {
        case .green: .green
        case .accent: .accentColor
        case .white: .white
        }
    }
}

/// Preferences for the system HUDs, stored under `systemHUD.*` in UserDefaults.
@MainActor
final class SystemHUDSettings: ObservableObject {
    enum Key {
        static let enableSystemHUD = "systemHUD.enabled"
        static let style = "systemHUD.style"
        static let enableVolumeHUD = "systemHUD.volumeHUD"
        static let enableMicrophoneHUD = "systemHUD.microphoneHUD"
        static let enableBrightnessHUD = "systemHUD.brightnessHUD"
        static let interceptMediaKeys = "systemHUD.interceptMediaKeys"
        static let volumeStepPercent = "systemHUD.volumeStepPercent"
        static let volumeFineStepPercent = "systemHUD.volumeFineStepPercent"
        static let playVolumeFeedback = "systemHUD.playVolumeFeedback"
        static let progressBarStyle = "systemHUD.progressBarStyle"
        static let showPercentages = "systemHUD.showPercentages"
        static let colorCodedVolume = "systemHUD.colorCodedVolume"
        static let smoothColorGradient = "systemHUD.smoothColorGradient"
        static let glowEffect = "systemHUD.glowEffect"
        static let useAccentColor = "systemHUD.useAccentColor"
        static let enableCapsLockIndicator = "systemHUD.capsLockIndicator"
        static let showCapsLockLabel = "systemHUD.capsLockLabel"
        static let capsLockTint = "systemHUD.capsLockTint"
    }

    /// Each step can be 1-25 % of the full range.
    static let stepRange = 1...25
    static let defaultVolumeStepPercent = 6
    static let defaultVolumeFineStepPercent = 2

    static let shared = SystemHUDSettings()

    private let defaults: UserDefaults

    /// Master switch (default on).
    @Published var enableSystemHUD: Bool {
        didSet { defaults.set(enableSystemHUD, forKey: Key.enableSystemHUD) }
    }
    /// Inline HUD, default on.
    @Published var style: SystemHUDStyle {
        didSet {
            defaults.set(style.rawValue, forKey: Key.style)
            // Resets the glow and the bar style when the inline style is chosen.
            if style == .inline, oldValue != .inline {
                glowEffect = false
                progressBarStyle = .hierarchical
            }
        }
    }
    @Published var enableVolumeHUD: Bool {
        didSet { defaults.set(enableVolumeHUD, forKey: Key.enableVolumeHUD) }
    }
    /// Shows the "Mic muted / unmuted" HUD when the default input device's mute flag changes.
    /// Brightness HUD for the built-in display (default: on).
    @Published var enableBrightnessHUD: Bool {
        didSet { defaults.set(enableBrightnessHUD, forKey: Key.enableBrightnessHUD) }
    }
    @Published var enableMicrophoneHUD: Bool {
        didSet { defaults.set(enableMicrophoneHUD, forKey: Key.enableMicrophoneHUD) }
    }
    /// Swallow the volume keys and apply the step here, so the macOS bezel stays hidden.
    /// Only takes effect once Accessibility is granted.
    @Published var interceptMediaKeys: Bool {
        didSet { defaults.set(interceptMediaKeys, forKey: Key.interceptMediaKeys) }
    }
    @Published var volumeStepPercent: Int {
        didSet { defaults.set(volumeStepPercent, forKey: Key.volumeStepPercent) }
    }
    /// Step used while Option and Shift are held.
    @Published var volumeFineStepPercent: Int {
        didSet { defaults.set(volumeFineStepPercent, forKey: Key.volumeFineStepPercent) }
    }
    @Published var playVolumeFeedback: Bool {
        didSet { defaults.set(playVolumeFeedback, forKey: Key.playVolumeFeedback) }
    }
    @Published var progressBarStyle: SystemHUDProgressBarStyle {
        didSet { defaults.set(progressBarStyle.rawValue, forKey: Key.progressBarStyle) }
    }
    @Published var showPercentages: Bool {
        didSet { defaults.set(showPercentages, forKey: Key.showPercentages) }
    }
    /// Green below 60 %, yellow to 85 %, red above.
    @Published var colorCodedVolume: Bool {
        didSet { defaults.set(colorCodedVolume, forKey: Key.colorCodedVolume) }
    }
    @Published var smoothColorGradient: Bool {
        didSet { defaults.set(smoothColorGradient, forKey: Key.smoothColorGradient) }
    }
    /// "Enable glowing effect".
    @Published var glowEffect: Bool {
        didSet { defaults.set(glowEffect, forKey: Key.glowEffect) }
    }
    /// Tints the indicator with the accent colour.
    @Published var useAccentColor: Bool {
        didSet { defaults.set(useAccentColor, forKey: Key.useAccentColor) }
    }
    @Published var enableCapsLockIndicator: Bool {
        didSet { defaults.set(enableCapsLockIndicator, forKey: Key.enableCapsLockIndicator) }
    }
    @Published var showCapsLockLabel: Bool {
        didSet { defaults.set(showCapsLockLabel, forKey: Key.showCapsLockLabel) }
    }
    @Published var capsLockTint: CapsLockTintMode {
        didSet { defaults.set(capsLockTint.rawValue, forKey: Key.capsLockTint) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enableSystemHUD = defaults.object(forKey: Key.enableSystemHUD) as? Bool ?? true
        style = SystemHUDStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .inline
        enableVolumeHUD = defaults.object(forKey: Key.enableVolumeHUD) as? Bool ?? true
        enableMicrophoneHUD = defaults.object(forKey: Key.enableMicrophoneHUD) as? Bool ?? true
        enableBrightnessHUD = defaults.object(forKey: Key.enableBrightnessHUD) as? Bool ?? true
        interceptMediaKeys = defaults.object(forKey: Key.interceptMediaKeys) as? Bool ?? true
        volumeStepPercent = Self.clampStep(
            defaults.object(forKey: Key.volumeStepPercent) as? Int ?? Self.defaultVolumeStepPercent
        )
        volumeFineStepPercent = Self.clampStep(
            defaults.object(forKey: Key.volumeFineStepPercent) as? Int ?? Self.defaultVolumeFineStepPercent
        )
        playVolumeFeedback = defaults.object(forKey: Key.playVolumeFeedback) as? Bool ?? false
        progressBarStyle = SystemHUDProgressBarStyle(
            rawValue: defaults.string(forKey: Key.progressBarStyle) ?? ""
        ) ?? .hierarchical
        showPercentages = defaults.object(forKey: Key.showPercentages) as? Bool ?? true
        colorCodedVolume = defaults.object(forKey: Key.colorCodedVolume) as? Bool ?? true
        smoothColorGradient = defaults.object(forKey: Key.smoothColorGradient) as? Bool ?? true
        glowEffect = defaults.object(forKey: Key.glowEffect) as? Bool ?? false
        useAccentColor = defaults.object(forKey: Key.useAccentColor) as? Bool ?? false
        enableCapsLockIndicator = defaults.object(forKey: Key.enableCapsLockIndicator) as? Bool ?? true
        showCapsLockLabel = defaults.object(forKey: Key.showCapsLockLabel) as? Bool ?? false
        capsLockTint = CapsLockTintMode(rawValue: defaults.string(forKey: Key.capsLockTint) ?? "") ?? .white
    }

    var usesInlineStyle: Bool { style == .inline }

    /// Fraction of full volume one key press moves.
    func volumeStep(fine: Bool) -> Float {
        Float(fine ? volumeFineStepPercent : volumeStepPercent) / 100
    }

    /// Accent colour, blue by default.
    static let accentColor = Color.blue

    static func clampStep(_ value: Int) -> Int {
        min(max(value, stepRange.lowerBound), stepRange.upperBound)
    }
}
