import Combine
import Foundation

/// Where Focus metadata comes from besides the system's Focus notifications.
enum FocusMonitoringMode: String, CaseIterable, Identifiable, Sendable {
    /// Notifications, plus the Focus database when Full Disk Access is granted.
    case standard
    /// Notifications, plus a `log stream` tail of duetexpertd for the mode name and identifier.
    case unifiedLog

    var id: Self { self }

    /// Settings labels for the same choice.
    var label: String {
        switch self {
        case .standard: "Use without DevTools"
        case .unifiedLog: "Use DevTools"
        }
    }
}

/// Focus preferences, stored under `focus.*` keys. Defaults: detection, the
/// indicator and its label on; persistent (not toast) presentation; standard monitoring.
@MainActor
final class FocusSettings: ObservableObject {
    enum Key {
        static let enableDoNotDisturbDetection = "focus.enableDoNotDisturbDetection"
        static let showDoNotDisturbIndicator = "focus.showDoNotDisturbIndicator"
        static let showDoNotDisturbLabel = "focus.showDoNotDisturbLabel"
        static let focusIndicatorNonPersistent = "focus.focusIndicatorNonPersistent"
        static let monitoringMode = "focus.monitoringMode"
    }

    static let shared = FocusSettings()

    private let defaults: UserDefaults

    @Published var enableDoNotDisturbDetection: Bool {
        didSet { defaults.set(enableDoNotDisturbDetection, forKey: Key.enableDoNotDisturbDetection) }
    }

    /// Show the Focus live activity on the closed notch and the glyph in the open header.
    @Published var showDoNotDisturbIndicator: Bool {
        didSet { defaults.set(showDoNotDisturbIndicator, forKey: Key.showDoNotDisturbIndicator) }
    }

    /// Show the mode's name in the right wing (persistent presentation only).
    @Published var showDoNotDisturbLabel: Bool {
        didSet { defaults.set(showDoNotDisturbLabel, forKey: Key.showDoNotDisturbLabel) }
    }

    /// Brief toast: "On" for 1.8 s when Focus starts and "Off" for 1.5 s when it ends.
    @Published var focusIndicatorNonPersistent: Bool {
        didSet { defaults.set(focusIndicatorNonPersistent, forKey: Key.focusIndicatorNonPersistent) }
    }

    @Published var monitoringMode: FocusMonitoringMode {
        didSet { defaults.set(monitoringMode.rawValue, forKey: Key.monitoringMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enableDoNotDisturbDetection = defaults.object(forKey: Key.enableDoNotDisturbDetection) as? Bool ?? true
        showDoNotDisturbIndicator = defaults.object(forKey: Key.showDoNotDisturbIndicator) as? Bool ?? true
        showDoNotDisturbLabel = defaults.object(forKey: Key.showDoNotDisturbLabel) as? Bool ?? true
        focusIndicatorNonPersistent = defaults.object(forKey: Key.focusIndicatorNonPersistent) as? Bool ?? false
        monitoringMode = FocusMonitoringMode(rawValue: defaults.string(forKey: Key.monitoringMode) ?? "") ?? .standard
    }
}
