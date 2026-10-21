import SwiftUI

/// Notes tab content: the notes list or the note editor, sliding over each other with a
/// spring, optionally beside the clipboard grid (split layout).
struct NotchNotesTabView: View {
    @ObservedObject var model: NotchViewModel
    @StateObject private var controller: NotesTabController
    @ObservedObject private var settings: NotesSettings
    @ObservedObject private var store: NotesStore
    @ObservedObject private var sync: AppleNotesSyncManager

    /// List and editor swap with this spring (response 0.35, damping 0.8).
    private static let paneAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// Without a controller the tab runs on the shared notes library, settings and sync; a
    /// controller passed in brings its own.
    init(model: NotchViewModel, controller: NotesTabController? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _controller = StateObject(wrappedValue: controller ?? NotesTabController())
        _settings = ObservedObject(wrappedValue: controller?.settings ?? .shared)
        _store = ObservedObject(wrappedValue: controller?.store ?? .shared)
        _sync = ObservedObject(wrappedValue: controller?.sync ?? .shared)
    }

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
