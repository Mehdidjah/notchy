import SwiftUI

/// The Shortcuts settings, laid out like Atoll's Settings › Shortcuts: a General section
/// with the master switch, then one section per feature (Media, Keep Awake, Navigation,
/// Timer, Clipboard, AI Assistant, Terminal, Color Picker) holding “Title:” recorder rows
/// and right-aligned caption footers. A row is disabled, with a “… is disabled” caption,
/// while its feature is off. With the master switch off, a single “Keyboard shortcuts are
/// disabled” section replaces the rows.
///
/// The body is a sequence of `Section`s; embed it in a grouped `Form`, or use
/// `ShortcutsSettingsPane` for a ready-made tab.
struct ShortcutsSettingsSection: View {
    @ObservedObject private var manager: ShortcutsManager
    @ObservedObject private var settings: ShortcutsSettings
    @ObservedObject private var layout: KeyboardLayout

    init(manager: ShortcutsManager = .shared, layout: KeyboardLayout = .shared) {
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: manager.settings)
        _layout = ObservedObject(wrappedValue: layout)
    }

    var body: some View {
        Section {
            Toggle(isOn: $settings.isEnabled) {
                Text("Enable global keyboard shortcuts")
            }
        } header: {
            Text("General")
        } footer: {
            footer("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
        }

        if settings.isEnabled {
            ForEach(visibleGroups) { group in
                Section {
                    ForEach(group.actions.filter(manager.isListed)) { action in
                        row(for: action, in: group)
                    }
                } header: {
                    Text(group.header)
                } footer: {
                    footer(footerText(for: group))
                }
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard shortcuts are disabled")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var visibleGroups: [ShortcutGroup] {
        ShortcutGroup.allCases.filter { group in group.actions.contains(where: manager.isListed) }
    }

    // MARK: - Rows

    /// Atoll builds its rows three ways: a bare recorder (Media, Navigation), a recorder over
    /// its caption (Keep Awake), and that stack pushed leading by a `Spacer` (the rest).
    @ViewBuilder
    private func row(for action: ShortcutAction, in group: ShortcutGroup) -> some View {
        switch group.rowLayout {
        case .bare:
            if caption(for: action) == nil {
                recorder(for: action)
            } else {
                stackedRow(for: action)
            }
        case .stacked:
            stackedRow(for: action)
        case .stackedWithSpacer:
            HStack {
                stackedRow(for: action)
                Spacer()
            }
        }
    }

    private func stackedRow(for action: ShortcutAction) -> some View {
        VStack(alignment: .leading) {
            recorder(for: action)
            if let caption = caption(for: action) {
                Text(caption.text)
                    .font(.caption)
                    .foregroundStyle(caption.color)
                    .padding(.top, 2)
            }
        }
    }

    /// `KeyboardShortcuts.Recorder("Title:", name:)`: a labelled row with the recorder trailing.
    private func recorder(for action: ShortcutAction) -> some View {
        LabeledContent {
            ShortcutRecorder(action: action, manager: manager, layout: layout)
        } label: {
            Text(action.recorderTitle)
        }
        .disabled(!settings.isEnabled || !manager.isAvailable(action))
    }

    private struct Caption {
        let text: String
        let color: Color
    }

    private func caption(for action: ShortcutAction) -> Caption? {
        if !manager.isAvailable(action) {
            return Caption(text: action.unavailableCaption, color: .secondary)
        }
        if let failure = manager.failures[action] {
            return Caption(text: failure.message, color: .orange)
        }
        return nil
    }

    // MARK: - Footers

    private func footer(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    private func footerText(for group: ShortcutGroup) -> String {
        switch group {
        case .media:
            return "Sneak Peek shows the media title and artist under the notch for a few seconds."
        case .keepAwake:
            return "Starts the default duration set in General, or ends a running session."
        case .navigation:
            return "Toggle the Dynamic Island open or closed from anywhere."
        case .timer:
            return "Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled."
        case .clipboard:
            _ = layout.revision
            let history: String
            if let shortcut = settings.shortcut(for: .clipboardHistoryPanel) {
                history = "Opens the clipboard history panel, currently \(shortcut.displayString)."
            } else {
                history = "Opens the clipboard history panel. No shortcut is set."
            }
            let extras = group.actions.contains(where: { $0 != .clipboardHistoryPanel && manager.isListed($0) })
                ? " Quick Paste opens the paste palette over the frontmost app, and Clipboard Library opens the full history window."
                : ""
            return history + extras + " Only works when clipboard feature is enabled."
        case .aiAssistant:
            return "Opens the AI assistant panel for file analysis and conversation. Default is Cmd+Shift+A. Only works when screen assistant feature is enabled."
        case .terminal:
            return "Opens the terminal tab in the notch. Default is Ctrl+`. Only works when terminal feature is enabled."
        case .colorPicker:
            return "Opens the color picker panel for screen color capture. Default is Cmd+Shift+P. Only works when color picker feature is enabled."
        }
    }
}

/// A complete Shortcuts tab for the Settings window: a grouped `Form` around
/// `ShortcutsSettingsSection`, as Atoll's Settings › Shortcuts.
struct ShortcutsSettingsPane: View {
    var body: some View {
        Form {
            ShortcutsSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}
