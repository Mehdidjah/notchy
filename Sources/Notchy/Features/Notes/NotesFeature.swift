import Combine
import Foundation
import SwiftUI

/// Entry point the app coordinator calls: loads the notes library, keeps the published Notes
/// layout in step with the settings, puts the Notes settings in the Settings window, and runs
/// Apple Notes sync when it is turned on.
@MainActor
enum NotesFeature {
    /// The Notes tab currently on screen, so shutdown can save an open draft.
    static weak var activeController: NotesTabController?

    private static var cancellables: Set<AnyCancellable> = []
    private static var isRunning = false

    static func start() {
        start(userSettings: nil)
    }

    /// Pass the host's settings to show the "Enable Notes" row (the Notes-tab toggle) at
    /// the top of the Notes settings pane.
    static func start(userSettings: UserSettings?) {
        guard !isRunning else { return }
        isRunning = true

        let settings = NotesSettings.shared
        let layout = NotesLayoutState.shared

        NotesStore.shared.loadIfNeeded()
        layout.setResting(showsClipboard: settings.showsClipboardBesideNotes)

        SettingsSectionRegistry.shared.register(.notes, id: "notes") {
            if let userSettings {
                NotesSettingsPane(userSettings: userSettings)
            } else {
                NotesSettingsSection()
            }
        }

        // While the tab is off screen, the next opening should already be the right height.
        settings.$showsClipboardBesideNotes
            .removeDuplicates()
            .dropFirst()
            .sink { showsClipboard in
                Task { @MainActor in
                    guard activeController?.isEditing != true else { return }
                    NotesLayoutState.shared.setResting(showsClipboard: showsClipboard)
                }
            }
            .store(in: &cancellables)

        // Turning sync on runs one straight away. Otherwise sync runs only when
        // the Notes tab appears or from "Sync Now", so Notes.app is not launched at login.
        settings.$appleNotesSyncEnabled
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { _ in
                Task { @MainActor in AppleNotesSyncManager.shared.requestSync() }
            }
            .store(in: &cancellables)
    }

    static func stop() {
        guard isRunning else { return }
        isRunning = false
        activeController?.persist()
        cancellables.removeAll()
        AppleNotesSyncManager.shared.cancel()
        NotesStore.shared.flushSynchronously()
    }
}

/// The Notes settings bound to the host's Notes-tab toggle, shown as "Enable Notes".
/// Observes the host settings so the rest of the pane hides and shows with that toggle.
struct NotesSettingsPane: View {
    @ObservedObject var userSettings: UserSettings

    var body: some View {
        NotesSettingsSection(showsTab: $userSettings.showNotesTab)
    }
}
