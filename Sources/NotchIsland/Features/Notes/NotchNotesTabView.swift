import SwiftUI

/// Notes tab content: the notes list or the note editor, sliding over each other with Atoll's
/// spring, optionally beside the clipboard grid (Atoll's split layout).
struct NotchNotesTabView: View {
    @ObservedObject var model: NotchViewModel
    @StateObject private var controller = NotesTabController()
    @ObservedObject private var settings = NotesSettings.shared
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var sync = AppleNotesSyncManager.shared

    /// List and editor swap with this spring (Atoll: response 0.35, damping 0.8).
    private static let paneAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)

    var body: some View {
        HStack(spacing: 0) {
            if settings.showsClipboardBesideNotes {
                NotchClipboardTabView(model: model)
                    .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.15))
            }

            ZStack {
                if controller.isEditing {
                    NoteEditorPane(controller: controller, settings: settings)
                        .transition(.move(edge: .trailing))
                } else {
                    NoteListPane(controller: controller, store: store, settings: settings, sync: sync)
                        .transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(Self.paneAnimation, value: controller.route)
            .onHover { inside in
                NotesLayoutState.shared.setPointerOverNotes(inside)
            }
            .background(NotesKeyboardBridge(controller: controller))
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            controller.viewAppeared { [weak model] held in
                model?.setKeyboardFocus(held)
            }
        }
        .onDisappear {
            controller.viewDisappeared()
        }
    }
}
