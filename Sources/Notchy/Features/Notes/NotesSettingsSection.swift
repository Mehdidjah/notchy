import SwiftUI

/// The Notes rows for the Settings window, mirroring Atoll's Notes pane: a General section and,
/// while notes are on, an Apple Notes section. Embed inside a `Form`.
struct NotesSettingsSection: View {
    @ObservedObject private var settings: NotesSettings
    @ObservedObject private var sync: AppleNotesSyncManager
    private let showsTab: Binding<Bool>?

    /// Pass the host's Notes-tab toggle as `showsTab` to show Atoll's "Enable Notes" row.
    init(
        showsTab: Binding<Bool>? = nil,
        settings: NotesSettings = .shared,
        sync: AppleNotesSyncManager = .shared
    ) {
        self.showsTab = showsTab
        _settings = ObservedObject(wrappedValue: settings)
        _sync = ObservedObject(wrappedValue: sync)
    }

    private var notesEnabled: Bool { showsTab?.wrappedValue ?? true }

    var body: some View {
        Section {
            if let showsTab {
                Toggle("Enable Notes", isOn: showsTab)
            }
            if notesEnabled {
                Toggle("Enable Note Pinning", isOn: $settings.pinningEnabled)
                Toggle("Enable Note Search", isOn: $settings.searchEnabled)
                Toggle("Enable Color Filtering", isOn: $settings.colorFilteringEnabled)
                Toggle("Enable Create from Clipboard", isOn: $settings.createFromClipboardEnabled)
                Toggle("Show Character Count", isOn: $settings.showsCharacterCount)
                Toggle("Show Clipboard beside Notes", isOn: $settings.showsClipboardBesideNotes)
            }
        } header: {
            Text("General")
        } footer: {
            Text("Customize how you organize and create notes. Enabling color filtering and search helps manage large lists.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if notesEnabled {
            Section {
                Toggle("Sync with Apple Notes", isOn: $settings.appleNotesSyncEnabled)

                if settings.appleNotesSyncEnabled {
                    Picker("Import from", selection: $settings.appleNotesSyncScope) {
                        ForEach(AppleNotesSyncScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }

                    Button {
                        sync.requestSync()
                    } label: {
                        HStack {
                            Text("Sync Now")
                            Spacer()
                            if sync.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(sync.isSyncing)

                    if let lastSync = settings.appleNotesLastSyncDate {
                        LabeledContent("Last synced") {
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = sync.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Apple Notes")
            } footer: {
                Text("Two-way sync with the macOS Notes app. Notes created here appear in the Notchy folder in Notes, and your Apple Notes are imported into the island; deleting an imported note here deletes it in Notes. Grant Automation permission for Notes when prompted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
