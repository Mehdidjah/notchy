import AppKit
import Carbon.HIToolbox

/// Why a recorded keystroke cannot simply be saved.
enum ShortcutIssue: Equatable, Sendable {
    /// No modifier, or Shift alone, on a key that types text. The recorder beeps and keeps
    /// listening, as Atoll's recorder does.
    case needsModifier
    /// Option or Option-Shift alone: macOS 15 and later reject these for global hot keys.
    case optionNeedsCommandOrControl
    /// Already bound to another NotchIsland action.
    case usedByAction(ShortcutAction)
    /// Already the key equivalent of one of the app's own menu items.
    case usedByMenuItem(String)
    /// Already a system-wide shortcut (Spotlight, Mission Control, screenshots, …).
    case usedBySystem

    /// The alert's headline, worded like the recorder Atoll ships.
    var message: String {
        switch self {
        case .needsModifier:
            "Shortcuts need Command or Control, unless they use a function key."
        case .optionNeedsCommandOrControl:
            "Option modifier must be combined with Command or Control."
        case let .usedByAction(action):
            "This keyboard shortcut is already used by “\(action.title)”."
        case let .usedByMenuItem(title):
            "This keyboard shortcut cannot be used as it’s already used by the “\(title)” menu item."
        case .usedBySystem:
            "This keyboard shortcut cannot be used as it’s already a system-wide keyboard shortcut."
        }
    }

    var informativeText: String? {
        switch self {
        case .usedBySystem:
            "Most system-wide keyboard shortcuts can be changed in “System Settings › Keyboard › Keyboard Shortcuts”."
        case .usedByAction:
            "Reassign it to use it here and leave the other action without a shortcut."
        default:
            nil
        }
    }

    /// Whether the user may keep the shortcut anyway (system and in-app clashes only).
    var canOverride: Bool {
        switch self {
        case .usedBySystem, .usedByAction: true
        default: false
        }
    }
}

enum ShortcutValidation {
    /// Keystrokes the window server consumes before any app sees them.
    private static let reserved: Set<Shortcut> = [
        Shortcut(kVK_Tab, [.command]),
        Shortcut(kVK_Tab, [.command, .shift]),
    ]

    /// Rules that need no system state: a modifier other than Shift is required unless the
    /// key is F1–F20, and from macOS 15 Option (or Option-Shift) needs Command or Control
    /// beside it, because the system no longer delivers such hot keys.
    static func structuralIssue(_ shortcut: Shortcut) -> ShortcutIssue? {
        if shortcut.isFunctionKey { return nil }
        let modifiers = shortcut.modifiers
        if modifiers.subtracting(.shift).isEmpty { return .needsModifier }
        if #available(macOS 15, *), !modifiers.contains(.command), !modifiers.contains(.control) {
            return .optionNeedsCommandOrControl
        }
        return nil
    }

    /// Whether the keystroke is a system-wide shortcut that is switched on in
    /// System Settings › Keyboard › Keyboard Shortcuts.
    @MainActor
    static func isTakenBySystem(_ shortcut: Shortcut) -> Bool {
        reserved.contains(shortcut) || systemShortcuts().contains(shortcut)
    }

    /// The enabled symbolic hot keys, read with the public `CopySymbolicHotKeys`.
    @MainActor
    static func systemShortcuts() -> Set<Shortcut> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        let enabledKey = kHISymbolicHotKeyEnabled as String
        let codeKey = kHISymbolicHotKeyCode as String
        let modifiersKey = kHISymbolicHotKeyModifiers as String
        var result: Set<Shortcut> = []
        for entry in entries {
            guard (entry[enabledKey] as? Bool) == true,
                  let code = (entry[codeKey] as? NSNumber)?.intValue,
                  let modifiers = (entry[modifiersKey] as? NSNumber)?.intValue,
                  code >= 0, code < 0xFFFF
            else { continue }
            if let shortcut = systemShortcut(keyCode: UInt32(code), carbonModifiers: UInt32(truncatingIfNeeded: modifiers)) {
                result.insert(shortcut)
            }
        }
        return result
    }

    /// Interprets one symbolic hot key. Entries that need the Fn/Globe key on an ordinary
    /// key (Globe-Q for Quick Note, Globe-F for full screen, …) can never collide with a hot
    /// key, which cannot include Fn, so they are skipped; on arrows, F-keys and the
    /// navigation block the Fn bit is implicit and ignored.
    static func systemShortcut(keyCode: UInt32, carbonModifiers: UInt32) -> Shortcut? {
        let shortcut = Shortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)
        let needsFn = carbonModifiers & UInt32(kEventKeyModifierFnMask) != 0
        if needsFn, !shortcut.carriesImplicitFn { return nil }
        if shortcut.modifiers.isEmpty, !shortcut.isFunctionKey { return nil }
        return shortcut
    }

    /// The title of a menu item in `menu` (the app's main menu by default) whose key
    /// equivalent matches `shortcut`.
    @MainActor
    static func menuItemTitle(using shortcut: Shortcut, in menu: NSMenu? = NSApp?.mainMenu) -> String? {
        guard let menu, let key = shortcut.menuKeyEquivalent?.lowercased(), !key.isEmpty else { return nil }
        return firstMatch(in: menu, key: key, modifiers: shortcut.modifiers)
    }

    @MainActor
    private static func firstMatch(in menu: NSMenu, key: String, modifiers: ShortcutModifiers) -> String? {
        for item in menu.items {
            if let submenu = item.submenu, let title = firstMatch(in: submenu, key: key, modifiers: modifiers) {
                return title
            }
            let equivalent = item.keyEquivalent
            guard !equivalent.isEmpty, equivalent.lowercased() == key else { continue }
            var itemModifiers = ShortcutModifiers(item.keyEquivalentModifierMask)
            // An uppercase letter as key equivalent implies Shift.
            if equivalent != equivalent.lowercased() { itemModifiers.insert(.shift) }
            if itemModifiers == modifiers { return item.title }
        }
        return nil
    }
}
