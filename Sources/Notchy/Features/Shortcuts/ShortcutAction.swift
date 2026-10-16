import Carbon.HIToolbox
import Foundation

/// Every action a global shortcut can trigger. Raw values keep Atoll's shortcut names
/// (`toggleNotchOpen`, `clipboardHistoryPanel`, …) so stored bindings line up with its
/// vocabulary; Notchy's own Quick Paste and Library actions follow the same style.
///
/// Case order is the order rows appear in Settings.
enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case toggleSneakPeek
    case toggleCaffeinate
    case toggleNotchOpen
    case startDemoTimer
    case clipboardHistoryPanel
    case quickPaste
    case openLibrary
    case screenAssistantPanel
    case toggleTerminalTab
    case colorPickerPanel

    var id: String { rawValue }

    /// Atoll's defaults, plus ⌃⌘V and ⌃⌘L for Notchy's Quick Paste and Library.
    var defaultShortcut: Shortcut? {
        switch self {
        case .toggleSneakPeek: Shortcut(kVK_ANSI_H, [.command, .shift])
        case .toggleCaffeinate: Shortcut(kVK_ANSI_K, [.command, .shift])
        case .toggleNotchOpen: Shortcut(kVK_ANSI_I, [.command, .shift])
        case .startDemoTimer: Shortcut(kVK_ANSI_T, [.command, .shift])
        case .clipboardHistoryPanel: Shortcut(kVK_ANSI_V, [.command, .shift])
        case .quickPaste: Shortcut(kVK_ANSI_V, [.control, .command])
        case .openLibrary: Shortcut(kVK_ANSI_L, [.control, .command])
        case .screenAssistantPanel: Shortcut(kVK_ANSI_A, [.command, .shift])
        case .toggleTerminalTab: Shortcut(kVK_ANSI_Grave, [.control])
        case .colorPickerPanel: Shortcut(kVK_ANSI_P, [.command, .shift])
        }
    }

    /// The action's name, as alerts quote it.
    var title: String {
        switch self {
        case .toggleSneakPeek: "Toggle Sneak Peek"
        case .toggleCaffeinate: "Toggle Keep Awake"
        case .toggleNotchOpen: "Toggle Notch Open"
        case .startDemoTimer: "Start Demo Timer"
        case .clipboardHistoryPanel: "Clipboard History"
        case .quickPaste: "Quick Paste"
        case .openLibrary: "Clipboard Library"
        case .screenAssistantPanel: "Screen Assistant"
        case .toggleTerminalTab: "Toggle Terminal Tab"
        case .colorPickerPanel: "Color Picker Panel"
        }
    }

    /// The recorder row's label, with the trailing colon Atoll uses.
    var recorderTitle: String { title + ":" }

    /// Shown under the row while the owning feature is switched off.
    var unavailableCaption: String {
        switch self {
        case .toggleSneakPeek: "Media feature is disabled"
        case .toggleCaffeinate: "Keep Awake is disabled"
        case .toggleNotchOpen: "The island is disabled"
        case .startDemoTimer: "Timer feature is disabled"
        case .clipboardHistoryPanel, .quickPaste, .openLibrary: "Clipboard feature is disabled"
        case .screenAssistantPanel: "Screen Assistant feature is disabled"
        case .toggleTerminalTab: "Terminal feature is disabled"
        case .colorPickerPanel: "Color Picker feature is disabled"
        }
    }

    var group: ShortcutGroup {
        switch self {
        case .toggleSneakPeek: .media
        case .toggleCaffeinate: .keepAwake
        case .toggleNotchOpen: .navigation
        case .startDemoTimer: .timer
        case .clipboardHistoryPanel, .quickPaste, .openLibrary: .clipboard
        case .screenAssistantPanel: .aiAssistant
        case .toggleTerminalTab: .terminal
        case .colorPickerPanel: .colorPicker
        }
    }

    /// Actions for features Notchy may not ship. Their rows only appear, and their keys
    /// are only claimed, once a handler is bound, so an absent feature never steals ⇧⌘A or ⌃`.
    var isListedOnlyWhenBound: Bool {
        switch self {
        case .screenAssistantPanel, .toggleTerminalTab: true
        default: false
        }
    }

    /// Identifier used with `HotKeyCenter`.
    var hotKeyID: String { "shortcuts." + rawValue }
}

/// The Settings sections, in Atoll's order: Media, Keep Awake, Navigation, Timer, Clipboard,
/// AI Assistant, Terminal, Color Picker.
enum ShortcutGroup: String, CaseIterable, Identifiable, Sendable {
    case media
    case keepAwake
    case navigation
    case timer
    case clipboard
    case aiAssistant
    case terminal
    case colorPicker

    var id: String { rawValue }

    var header: String {
        switch self {
        case .media: "Media"
        case .keepAwake: "Keep Awake"
        case .navigation: "Navigation"
        case .timer: "Timer"
        case .clipboard: "Clipboard"
        case .aiAssistant: "AI Assistant"
        case .terminal: "Terminal"
        case .colorPicker: "Color Picker"
        }
    }

    var actions: [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.group == self }
    }

    /// How Atoll's Shortcuts tab builds this section's rows.
    enum RowLayout: Sendable {
        /// The recorder alone (Media, Navigation).
        case bare
        /// `VStack(alignment: .leading) { recorder; caption }` (Keep Awake).
        case stacked
        /// `HStack { VStack(alignment: .leading) { recorder; caption }; Spacer() }`.
        case stackedWithSpacer
    }

    var rowLayout: RowLayout {
        switch self {
        case .media, .navigation: .bare
        case .keepAwake: .stacked
        case .timer, .clipboard, .aiAssistant, .terminal, .colorPicker: .stackedWithSpacer
        }
    }
}
