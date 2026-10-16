import Combine
import Foundation

/// Shortcut preferences, stored under `shortcuts.*` in UserDefaults.
///
/// Each binding lives at `shortcuts.binding.<action>`: absent means "use the default", a
/// `{keyCode, modifiers}` dictionary (Carbon modifier mask) is a custom shortcut, and an
/// empty dictionary means the user cleared it, so it does not fall back to the default.
@MainActor
final class ShortcutsSettings: ObservableObject {
    enum Key {
        /// Atoll's `enableShortcuts`.
        static let isEnabled = "shortcuts.enabled"
        static let bindingPrefix = "shortcuts.binding."

        static func binding(_ action: ShortcutAction) -> String { bindingPrefix + action.rawValue }
    }

    private enum Field {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

    static let shared = ShortcutsSettings()

    private let defaults: UserDefaults

    /// The master switch; off releases every global shortcut.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Effective shortcut per action; an action without an entry has none.
    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        var loaded: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            if let shortcut = Self.load(action, from: defaults) {
                loaded[action] = shortcut
            }
        }
        shortcuts = loaded
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? { shortcuts[action] }

    /// Whether the action still uses its built-in default.
    func isDefault(_ action: ShortcutAction) -> Bool {
        defaults.object(forKey: Key.binding(action)) == nil
    }

    var allDefaults: Bool { ShortcutAction.allCases.allSatisfy(isDefault) }

    /// Stores a custom shortcut, or clears the action when `shortcut` is nil.
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut {
            if shortcut == action.defaultShortcut {
                defaults.removeObject(forKey: Key.binding(action))
            } else {
                defaults.set(
                    [Field.keyCode: Int(shortcut.keyCode), Field.modifiers: Int(shortcut.carbonModifiers)],
                    forKey: Key.binding(action)
                )
            }
        } else {
            defaults.set([String: Int](), forKey: Key.binding(action))
        }
        shortcuts[action] = shortcut
    }

    func resetToDefault(_ action: ShortcutAction) {
        defaults.removeObject(forKey: Key.binding(action))
        shortcuts[action] = action.defaultShortcut
    }

    func resetAllToDefaults() {
        var restored: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            defaults.removeObject(forKey: Key.binding(action))
            restored[action] = action.defaultShortcut
        }
        shortcuts = restored
    }

    /// The action, other than `excluded`, that currently uses `shortcut`.
    func action(using shortcut: Shortcut, excluding excluded: ShortcutAction? = nil) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != excluded && shortcuts[$0] == shortcut }
    }

    private static func load(_ action: ShortcutAction, from defaults: UserDefaults) -> Shortcut? {
        guard let stored = defaults.object(forKey: Key.binding(action)) else {
            return action.defaultShortcut
        }
        guard let fields = stored as? [String: Any],
              let keyCode = (fields[Field.keyCode] as? NSNumber)?.intValue,
              let modifiers = (fields[Field.modifiers] as? NSNumber)?.intValue,
              (0..<0xFFFF).contains(keyCode)
        else {
            // An empty dictionary is a deliberate "no shortcut"; anything unreadable falls
            // back to the default rather than leaving the action silently unbound.
            if let fields = stored as? [String: Any], fields.isEmpty { return nil }
            return action.defaultShortcut
        }
        return Shortcut(keyCode: UInt32(keyCode), carbonModifiers: UInt32(truncatingIfNeeded: modifiers))
    }
}
