import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The four modifier keys a global shortcut may use, independent of the AppKit and Carbon
/// encodings so the value stays `Sendable` and trivially comparable.
struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue & 0x0F
    }

    /// Keeps only ⌃⌥⇧⌘ from AppKit flags; Caps Lock, Fn and the keypad bit are ignored.
    init(_ flags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }

    /// Reads a Carbon modifier mask (`cmdKey`, `shiftKey`, …), as used by
    /// `RegisterEventHotKey` and the system's symbolic hot keys.
    init(carbon: UInt32) {
        var value: ShortcutModifiers = []
        if carbon & UInt32(controlKey) != 0 { value.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { value.insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { value.insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { value.insert(.command) }
        self = value
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if contains(.control) { modifiers.insert(.control) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// Glyphs in the order macOS menus print them: ⌃ ⌥ ⇧ ⌘.
    var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    /// Spoken names in the same order, for VoiceOver.
    var spokenNames: [String] {
        var names: [String] = []
        if contains(.control) { names.append("Control") }
        if contains(.option) { names.append("Option") }
        if contains(.shift) { names.append("Shift") }
        if contains(.command) { names.append("Command") }
        return names
    }
}

/// A global keyboard shortcut: a layout-independent Carbon virtual key code plus modifiers.
///
/// Key codes name physical key positions (`kVK_ANSI_V` is the key labelled V on a US
/// keyboard), which is what the Carbon hot-key API matches. Only the displayed glyph follows
/// the active keyboard layout, so ⇧⌘V still reads correctly on AZERTY or Dvorak.
struct Shortcut: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers

    init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Convenience for the Carbon `kVK_*` constants, which import as `Int`.
    init(_ virtualKey: Int, _ modifiers: ShortcutModifiers) {
        self.init(keyCode: UInt32(truncatingIfNeeded: virtualKey), modifiers: modifiers)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.init(keyCode: keyCode, modifiers: ShortcutModifiers(carbon: carbonModifiers))
    }

    /// The shortcut a key event spells, or nil for events that carry no key.
    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: ShortcutModifiers(event.modifierFlags))
    }

    var carbonModifiers: UInt32 { modifiers.carbonFlags }

    /// F1 to F20 may be bound without modifiers, as in System Settings.
    var isFunctionKey: Bool { Self.functionKeyNumbers[keyCode] != nil }

    /// Keys macOS reports with the Fn flag set even when Fn is not held: F-keys, arrows and
    /// the Home/End/Page/Forward-Delete/Help block.
    var carriesImplicitFn: Bool {
        isFunctionKey || Self.implicitFnKeys.contains(keyCode)
    }

    /// Escape, Delete, Return and friends, which never depend on the keyboard layout.
    var specialKeyName: String? { Self.specialKeyNames[keyCode] }

    /// What the key prints on a US (ANSI) keyboard, used when no layout data is available.
    var fallbackKeyName: String? { Self.ansiKeyNames[keyCode] }

    /// The key's glyph as the current ASCII-capable layout prints it, uppercased like menu
    /// items (KeyboardShortcuts' recorder text).
    @MainActor
    var keyName: String {
        if let special = specialKeyName { return special }
        if let translated = KeyboardLayout.shared.character(for: keyCode) { return translated }
        return fallbackKeyName ?? String(format: "Key %u", keyCode)
    }

    /// The compact form shown in recorders and menus, for example `⇧⌘V`.
    @MainActor
    var displayString: String { displayString(keyName: keyName) }

    /// Formats with an explicit key glyph; pure, so tests do not depend on the active layout.
    func displayString(keyName: String) -> String {
        modifiers.symbols + keyName
    }

    /// A VoiceOver-friendly spelling, for example "Shift Command V".
    @MainActor
    var spokenDescription: String {
        let key = Self.spokenKeyNames[keyCode] ?? keyName
        return (modifiers.spokenNames + [key]).joined(separator: " ")
    }

    // MARK: - Key equivalents

    /// The same keystroke as a SwiftUI key equivalent, for in-app buttons and menus.
    @MainActor
    var keyEquivalent: KeyEquivalent? {
        if let special = Self.specialKeyEquivalents[keyCode] { return special }
        if let number = Self.functionKeyNumbers[keyCode],
           let scalar = Unicode.Scalar(UInt32(NSF1FunctionKey) + UInt32(number - 1)) {
            return KeyEquivalent(Character(scalar))
        }
        guard let character = KeyboardLayout.shared.character(for: keyCode, uppercased: false, source: .current)
            ?? fallbackKeyName?.lowercased(),
              character.count == 1,
              let first = character.first
        else { return nil }
        return KeyEquivalent(first)
    }

    /// The string `NSMenuItem.keyEquivalent` expects (lowercase for letters).
    @MainActor
    var menuKeyEquivalent: String? {
        keyEquivalent.map { String($0.character) }
    }

    // MARK: - Key tables

    private static let functionKeyNumbers: [UInt32: Int] = {
        let codes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        var table: [UInt32: Int] = [:]
        for (index, code) in codes.enumerated() {
            table[UInt32(code)] = index + 1
        }
        return table
    }()

    private static let implicitFnKeys: Set<UInt32> = [
        UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow), UInt32(kVK_DownArrow), UInt32(kVK_UpArrow),
        UInt32(kVK_Home), UInt32(kVK_End), UInt32(kVK_PageUp), UInt32(kVK_PageDown),
        UInt32(kVK_ForwardDelete), UInt32(kVK_Help),
    ]

    private static let specialKeyNames: [UInt32: String] = {
        var table: [UInt32: String] = [
            UInt32(kVK_Return): "↩",
            UInt32(kVK_ANSI_KeypadEnter): "⌤",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Help): "?⃝",
            UInt32(kVK_Home): "↖",
            UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_ANSI_KeypadClear): "⌧",
        ]
        for (code, number) in functionKeyNumbers {
            table[code] = "F\(number)"
        }
        return table
    }()

    private static let spokenKeyNames: [UInt32: String] = {
        var table: [UInt32: String] = [
            UInt32(kVK_Return): "Return",
            UInt32(kVK_ANSI_KeypadEnter): "Enter",
            UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Delete): "Delete",
            UInt32(kVK_ForwardDelete): "Forward Delete",
            UInt32(kVK_Escape): "Escape",
            UInt32(kVK_Help): "Help",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "Page Up",
            UInt32(kVK_PageDown): "Page Down",
            UInt32(kVK_LeftArrow): "Left Arrow",
            UInt32(kVK_RightArrow): "Right Arrow",
            UInt32(kVK_DownArrow): "Down Arrow",
            UInt32(kVK_UpArrow): "Up Arrow",
            UInt32(kVK_ANSI_KeypadClear): "Clear",
        ]
        for (code, number) in functionKeyNumbers {
            table[code] = "F\(number)"
        }
        return table
    }()

    private static let specialKeyEquivalents: [UInt32: KeyEquivalent] = [
        UInt32(kVK_Return): .return,
        UInt32(kVK_ANSI_KeypadEnter): .return,
        UInt32(kVK_Tab): .tab,
        UInt32(kVK_Space): .space,
        UInt32(kVK_Delete): .delete,
        UInt32(kVK_ForwardDelete): .deleteForward,
        UInt32(kVK_Escape): .escape,
        UInt32(kVK_Home): .home,
        UInt32(kVK_End): .end,
        UInt32(kVK_PageUp): .pageUp,
        UInt32(kVK_PageDown): .pageDown,
        UInt32(kVK_LeftArrow): .leftArrow,
        UInt32(kVK_RightArrow): .rightArrow,
        UInt32(kVK_DownArrow): .downArrow,
        UInt32(kVK_UpArrow): .upArrow,
        UInt32(kVK_ANSI_KeypadClear): .clear,
    ]

    private static let ansiKeyNames: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Grave, "`"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="),
            (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_Keypad0, "0"), (kVK_ANSI_Keypad1, "1"), (kVK_ANSI_Keypad2, "2"),
            (kVK_ANSI_Keypad3, "3"), (kVK_ANSI_Keypad4, "4"), (kVK_ANSI_Keypad5, "5"),
            (kVK_ANSI_Keypad6, "6"), (kVK_ANSI_Keypad7, "7"), (kVK_ANSI_Keypad8, "8"),
            (kVK_ANSI_Keypad9, "9"), (kVK_ANSI_KeypadDecimal, "."), (kVK_ANSI_KeypadMultiply, "*"),
            (kVK_ANSI_KeypadPlus, "+"), (kVK_ANSI_KeypadMinus, "-"), (kVK_ANSI_KeypadDivide, "/"),
            (kVK_ANSI_KeypadEquals, "="),
        ]
        var table: [UInt32: String] = [:]
        for (code, name) in pairs {
            table[UInt32(code)] = name
        }
        return table
    }()
}

extension NSMenuItem {
    /// Shows `shortcut` as this item's key equivalent, or removes it when nil. Lets menus
    /// mirror a global shortcut the user has rebound.
    @MainActor
    func applyShortcut(_ shortcut: Shortcut?) {
        guard let shortcut, let key = shortcut.menuKeyEquivalent else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
            return
        }
        keyEquivalent = key
        keyEquivalentModifierMask = shortcut.modifiers.eventFlags
    }
}
