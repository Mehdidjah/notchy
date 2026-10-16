import Combine
import Foundation

/// Bluetooth audio HUD preferences, stored under `bluetooth.*` in UserDefaults with Atoll's
/// defaults.
@MainActor
final class BluetoothSettings: ObservableObject {
    enum Key {
        static let showDeviceConnections = "bluetooth.showDeviceConnections"
        static let useInlineHUD = "bluetooth.useInlineHUD"
        static let useCircularBatteryIndicator = "bluetooth.useCircularBatteryIndicator"
        static let showBatteryPercentageText = "bluetooth.showBatteryPercentageText"
        static let showDeviceNameMarquee = "bluetooth.showDeviceNameMarquee"
        static let useColorCodedBatteryDisplay = "bluetooth.useColorCodedBatteryDisplay"
        static let useSmoothColorGradient = "bluetooth.useSmoothColorGradient"
        static let readBatteryLevels = "bluetooth.readBatteryLevels"
    }

    static let shared = BluetoothSettings()

    private let defaults: UserDefaults

    /// Show a HUD when headphones, AirPods or a speaker connect.
    @Published var showDeviceConnections: Bool {
        didSet { defaults.set(showDeviceConnections, forKey: Key.showDeviceConnections) }
    }
    /// Atoll's inline HUD (beside the notch) instead of a sneak-peek row under it.
    @Published var useInlineHUD: Bool {
        didSet { defaults.set(useInlineHUD, forKey: Key.useInlineHUD) }
    }
    /// A ring instead of a bar for the device's battery.
    @Published var useCircularBatteryIndicator: Bool {
        didSet { defaults.set(useCircularBatteryIndicator, forKey: Key.useCircularBatteryIndicator) }
    }
    @Published var showBatteryPercentageText: Bool {
        didSet { defaults.set(showBatteryPercentageText, forKey: Key.showBatteryPercentageText) }
    }
    /// Scroll the device name beside its icon.
    @Published var showDeviceNameMarquee: Bool {
        didSet { defaults.set(showDeviceNameMarquee, forKey: Key.showDeviceNameMarquee) }
    }
    /// Green-to-red battery colours instead of white.
    @Published var useColorCodedBatteryDisplay: Bool {
        didSet { defaults.set(useColorCodedBatteryDisplay, forKey: Key.useColorCodedBatteryDisplay) }
    }
    /// Blend between green, yellow and red instead of snapping.
    @Published var useSmoothColorGradient: Bool {
        didSet { defaults.set(useSmoothColorGradient, forKey: Key.useSmoothColorGradient) }
    }
    /// Ask `system_profiler` for the device's battery when it connects.
    @Published var readBatteryLevels: Bool {
        didSet { defaults.set(readBatteryLevels, forKey: Key.readBatteryLevels) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        showDeviceConnections = bool(Key.showDeviceConnections, true)
        useInlineHUD = bool(Key.useInlineHUD, true)
        useCircularBatteryIndicator = bool(Key.useCircularBatteryIndicator, true)
        showBatteryPercentageText = bool(Key.showBatteryPercentageText, false)
        showDeviceNameMarquee = bool(Key.showDeviceNameMarquee, false)
        useColorCodedBatteryDisplay = bool(Key.useColorCodedBatteryDisplay, true)
        useSmoothColorGradient = bool(Key.useSmoothColorGradient, true)
        readBatteryLevels = bool(Key.readBatteryLevels, true)
    }
}
