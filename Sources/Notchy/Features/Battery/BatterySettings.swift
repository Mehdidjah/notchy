import Combine
import Foundation

/// Battery preferences, stored under `battery.*` in UserDefaults with Atoll's defaults.
@MainActor
final class BatterySettings: ObservableObject {
    enum Key {
        static let showBatteryIndicator = "battery.showBatteryIndicator"
        static let showBatteryPercentage = "battery.showBatteryPercentage"
        static let showBatteryPercentInside = "battery.showBatteryPercentInside"
        static let showPowerStatusIcons = "battery.showPowerStatusIcons"
        static let showPowerStatusNotifications = "battery.showPowerStatusNotifications"
        static let playLowBatteryAlertSound = "battery.playLowBatteryAlertSound"
        static let showChargingHUD = "battery.showChargingHUD"
        static let showLowBatteryHUD = "battery.showLowBatteryHUD"
        static let showFullBatteryHUD = "battery.showFullBatteryHUD"
        static let chargingHUDDuration = "battery.chargingHUDDuration"
        static let lowBatteryHUDDuration = "battery.lowBatteryHUDDuration"
        static let fullBatteryHUDDuration = "battery.fullBatteryHUDDuration"
        static let lowBatteryThreshold = "battery.lowBatteryThreshold"
        static let fullBatteryThreshold = "battery.fullBatteryThreshold"
        static let lowBatteryHUDStyle = "battery.lowBatteryHUDStyle"
        static let fullBatteryHUDStyle = "battery.fullBatteryHUDStyle"
    }

    /// Slider ranges from Atoll's Battery pane.
    static let durationRange = 1...10
    static let lowThresholdRange = 5...30
    static let fullThresholdRange = 80...100
    static let defaultDuration = 3
    static let defaultLowThreshold = 20
    static let defaultFullThreshold = 100

    static let shared = BatterySettings()

    private let defaults: UserDefaults

    /// The battery in the open island's header. The header hides it on Macs without one.
    @Published var showBatteryIndicator: Bool {
        didSet { defaults.set(showBatteryIndicator, forKey: Key.showBatteryIndicator) }
    }
    /// The "NN%" label beside the battery (only when the figure is not drawn inside it).
    @Published var showBatteryPercentage: Bool {
        didSet { defaults.set(showBatteryPercentage, forKey: Key.showBatteryPercentage) }
    }
    /// Draws the figure inside a filled battery instead of beside an outlined one.
    @Published var showBatteryPercentInside: Bool {
        didSet { defaults.set(showBatteryPercentInside, forKey: Key.showBatteryPercentInside) }
    }
    /// Bolt or plug glyph on the header battery while on power.
    @Published var showPowerStatusIcons: Bool {
        didSet { defaults.set(showPowerStatusIcons, forKey: Key.showPowerStatusIcons) }
    }
    /// Master switch for the charging, low and full alerts.
    @Published var showPowerStatusNotifications: Bool {
        didSet { defaults.set(showPowerStatusNotifications, forKey: Key.showPowerStatusNotifications) }
    }
    @Published var playLowBatteryAlertSound: Bool {
        didSet { defaults.set(playLowBatteryAlertSound, forKey: Key.playLowBatteryAlertSound) }
    }
    @Published var showChargingHUD: Bool {
        didSet { defaults.set(showChargingHUD, forKey: Key.showChargingHUD) }
    }
    @Published var showLowBatteryHUD: Bool {
        didSet { defaults.set(showLowBatteryHUD, forKey: Key.showLowBatteryHUD) }
    }
    @Published var showFullBatteryHUD: Bool {
        didSet { defaults.set(showFullBatteryHUD, forKey: Key.showFullBatteryHUD) }
    }
    /// Seconds each alert stays up.
    @Published var chargingHUDDuration: Int {
        didSet { defaults.set(chargingHUDDuration, forKey: Key.chargingHUDDuration) }
    }
    @Published var lowBatteryHUDDuration: Int {
        didSet { defaults.set(lowBatteryHUDDuration, forKey: Key.lowBatteryHUDDuration) }
    }
    @Published var fullBatteryHUDDuration: Int {
        didSet { defaults.set(fullBatteryHUDDuration, forKey: Key.fullBatteryHUDDuration) }
    }
    /// Percent at or below which the low alert fires while on battery.
    @Published var lowBatteryThreshold: Int {
        didSet { defaults.set(lowBatteryThreshold, forKey: Key.lowBatteryThreshold) }
    }
    /// Percent at or above which the full alert fires while charging.
    @Published var fullBatteryThreshold: Int {
        didSet { defaults.set(fullBatteryThreshold, forKey: Key.fullBatteryThreshold) }
    }
    @Published var lowBatteryHUDStyle: BatteryHUDStyle {
        didSet { defaults.set(lowBatteryHUDStyle.rawValue, forKey: Key.lowBatteryHUDStyle) }
    }
    @Published var fullBatteryHUDStyle: BatteryHUDStyle {
        didSet { defaults.set(fullBatteryHUDStyle.rawValue, forKey: Key.fullBatteryHUDStyle) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        func int(_ key: String, _ fallback: Int, in range: ClosedRange<Int>) -> Int {
            let stored = defaults.object(forKey: key) as? Int ?? fallback
            return min(max(stored, range.lowerBound), range.upperBound)
        }
        func style(_ key: String) -> BatteryHUDStyle {
            BatteryHUDStyle(rawValue: defaults.string(forKey: key) ?? "") ?? .standard
        }
        showBatteryIndicator = bool(Key.showBatteryIndicator, true)
        showBatteryPercentage = bool(Key.showBatteryPercentage, true)
        showBatteryPercentInside = bool(Key.showBatteryPercentInside, true)
        showPowerStatusIcons = bool(Key.showPowerStatusIcons, true)
        showPowerStatusNotifications = bool(Key.showPowerStatusNotifications, true)
        playLowBatteryAlertSound = bool(Key.playLowBatteryAlertSound, true)
        showChargingHUD = bool(Key.showChargingHUD, true)
        showLowBatteryHUD = bool(Key.showLowBatteryHUD, true)
        showFullBatteryHUD = bool(Key.showFullBatteryHUD, true)
        chargingHUDDuration = int(Key.chargingHUDDuration, Self.defaultDuration, in: Self.durationRange)
        lowBatteryHUDDuration = int(Key.lowBatteryHUDDuration, Self.defaultDuration, in: Self.durationRange)
        fullBatteryHUDDuration = int(Key.fullBatteryHUDDuration, Self.defaultDuration, in: Self.durationRange)
        lowBatteryThreshold = int(Key.lowBatteryThreshold, Self.defaultLowThreshold, in: Self.lowThresholdRange)
        fullBatteryThreshold = int(Key.fullBatteryThreshold, Self.defaultFullThreshold, in: Self.fullThresholdRange)
        lowBatteryHUDStyle = style(Key.lowBatteryHUDStyle)
        fullBatteryHUDStyle = style(Key.fullBatteryHUDStyle)
    }

    func isHUDEnabled(_ kind: BatteryHUDKind) -> Bool {
        switch kind {
        case .charging: showChargingHUD
        case .lowBattery: showLowBatteryHUD
        case .fullBattery: showFullBatteryHUD
        }
    }

    /// Seconds the alert stays up; never less than one, as in Atoll.
    func duration(for kind: BatteryHUDKind) -> Int {
        let seconds = switch kind {
        case .charging: chargingHUDDuration
        case .lowBattery: lowBatteryHUDDuration
        case .fullBattery: fullBatteryHUDDuration
        }
        return max(1, seconds)
    }

    /// Charging is always the compact row; low and full follow their style settings.
    func style(for kind: BatteryHUDKind) -> BatteryHUDStyle {
        switch kind {
        case .charging: .compact
        case .lowBattery: lowBatteryHUDStyle
        case .fullBattery: fullBatteryHUDStyle
        }
    }
}
