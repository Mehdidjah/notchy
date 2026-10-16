import Combine
import Foundation

/// Keep Awake preferences, stored under `caffeinate.*` in UserDefaults with Atoll's defaults:
/// enabled, header icon shown, "Until turned off" and display kept awake. The ⇧⌘K shortcut
/// belongs to the Shortcuts feature (`ShortcutAction.toggleCaffeinate`).
@MainActor
final class CaffeinateSettings: ObservableObject {
    enum Key {
        static let isEnabled = "caffeinate.enabled"
        static let showHeaderButton = "caffeinate.showHeaderButton"
        static let defaultDuration = "caffeinate.defaultDuration"
        static let keepsDisplayAwake = "caffeinate.keepsDisplayAwake"
    }

    static let shared = CaffeinateSettings()

    private let defaults: UserDefaults

    /// Turning this off also ends a running session.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    @Published var showHeaderButton: Bool {
        didSet { defaults.set(showHeaderButton, forKey: Key.showHeaderButton) }
    }
    /// What the ⇧⌘K shortcut (`CaffeinateController.toggle()`) starts.
    @Published var defaultDuration: CaffeinateDuration {
        didSet { defaults.set(defaultDuration.rawValue, forKey: Key.defaultDuration) }
    }
    /// Off lets the screen sleep while the system stays up.
    @Published var keepsDisplayAwake: Bool {
        didSet { defaults.set(keepsDisplayAwake, forKey: Key.keepsDisplayAwake) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        showHeaderButton = defaults.object(forKey: Key.showHeaderButton) as? Bool ?? true
        defaultDuration = CaffeinateDuration(rawValue: defaults.string(forKey: Key.defaultDuration) ?? "")
            ?? .indefinite
        keepsDisplayAwake = defaults.object(forKey: Key.keepsDisplayAwake) as? Bool ?? true
    }
}
