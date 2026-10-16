import AppKit
import Combine
import SwiftUI

/// State of the Notes tab while it is on screen: which pane shows, the editor's draft, the
/// 1.5-s auto-save, pasting, and the layout height published to the host.
@MainActor
final class NotesTabController: ObservableObject {
    enum Route: Equatable {
        case list
        case editor(noteID: UUID, isNew: Bool)
    }

    /// An open note is saved 1.5 s after the last edit.
    static let defaultAutoSaveDelay: Duration = .milliseconds(1500)
    /// The editor keeps its text until the slide-out has finished.
    static let draftClearDelay: Duration = .milliseconds(300)

    @Published private(set) var route: Route = .list
    @Published var title = "" {
        didSet { if title != oldValue { draftDidChange() } }
    }
    @Published var content = "" {
        didSet { if content != oldValue { draftDidChange() } }
    }
    @Published var colorIndex = 0 {
        didSet { if colorIndex != oldValue { draftDidChange() } }
    }
    /// Picture shown in the editor's corner.
    @Published private(set) var image: NSImage?

    let store: NotesStore
    let settings: NotesSettings
    let layout: NotesLayoutState
    let sync: AppleNotesSyncManager

    /// The window hosting the tab; made key so a new note can be typed into at once.
    weak var hostWindow: NSWindow?

    private let autoSaveDelay: Duration
    private var imageData: Data?
    private var imageChange: NoteImageChange = .unchanged
    private var isLoadingDraft = false
    private var autoSaveTask: Task<Void, Never>?
    private var clearDraftTask: Task<Void, Never>?
    private var islandHold: ((Bool) -> Void)?
    private var isHoldingIsland = false
    private var settingsObservation: AnyCancellable?

    init(
        store: NotesStore = .shared,
        settings: NotesSettings = .shared,
        layout: NotesLayoutState = .shared,
        sync: AppleNotesSyncManager = .shared,
        autoSaveDelay: Duration = NotesTabController.defaultAutoSaveDelay
    ) {
        self.store = store
        self.settings = settings
        self.layout = layout
        self.sync = sync
        self.autoSaveDelay = autoSaveDelay
    }

    var isEditing: Bool { route != .list }

    var isEditingNewNote: Bool {
        if case .editor(_, true) = route { return true }
        return false
    }

    var editingNoteID: UUID? {
        if case .editor(let id, _) = route { return id }
        return nil
    }

    // MARK: - Lifecycle

    /// `hold(true)` keeps the island open (a confirmation is showing); `hold(false)` releases it.
    func viewAppeared(hold: @escaping (Bool) -> Void) {
        islandHold = hold
        store.loadIfNeeded()
        NotesFeature.activeController = self
        settingsObservation = settings.$showsClipboardBesideNotes
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateLayout() }
            }
        updateLayout()
        sync.requestSync()
    }

    /// The tab left the screen (another tab, or the island closed): save and reset.
    func viewDisappeared() {
        if isEditing { persist() }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        settingsObservation = nil
        setIslandHold(false)
        layout.setPointerOverNotes(false)
        layout.setResting(showsClipboard: settings.showsClipboardBesideNotes)
        if NotesFeature.activeController === self { NotesFeature.activeController = nil }
    }

    func updateLayout() {
        if isEditing {
            layout.setMode(.editor)
        } else {
            layout.setResting(showsClipboard: settings.showsClipboardBesideNotes)
        }
    }

    func setIslandHold(_ held: Bool) {
        guard held != isHoldingIsland else { return }
        isHoldingIsland = held
        islandHold?(held)
    }

    // MARK: - Opening and closing notes

    func createNote(content initialContent: String = "", imageData initialImage: Data? = nil) {
        loadDraft(
            route: .editor(noteID: UUID(), isNew: true),
            title: "",
            content: initialContent,
            colorIndex: 0,
            imageData: initialImage,
            imageChange: initialImage.map(NoteImageChange.replaced) ?? .unchanged
        )
    }

    func open(_ note: NoteItem) {
        loadDraft(
            route: .editor(noteID: note.id, isNew: false),
            title: note.title,
            content: note.content,
            colorIndex: note.colorIndex,
            imageData: store.imageData(for: note),
            imageChange: .unchanged
        )
    }

    /// "Done": save and return to the list.
    func done() {
        persist()
        closeEditor()
    }

    /// "< Notes": saves on the way back too.
    func back() {
        persist()
        closeEditor()
    }

    func setImage(_ data: Data?) {
        imageData = data
        image = data.flatMap(NSImage.init(data:))
        imageChange = data.map(NoteImageChange.replaced) ?? .removed
        draftDidChange()
    }

    /// Saves the open draft. Safe to call at any time; does nothing on the list.
    func persist() {
        guard let id = editingNoteID else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        let result = store.save(id: id, title: title, content: content, colorIndex: colorIndex, image: imageChange)
        if result != nil { imageChange = .unchanged }
        if let result, result.didChange {
            sync.push(noteID: result.note.id)
        }
    }

    // MARK: - List actions

    func togglePin(_ note: NoteItem) {
        store.togglePin(id: note.id)
    }

    func delete(_ note: NoteItem) {
        if let removed = store.delete(id: note.id) {
            sync.deleteRemote(of: removed)
        }
    }

    func deleteAll() {
        for note in store.deleteAll() {
            sync.deleteRemote(of: note)
        }
    }

    func copy(_ note: NoteItem) {
        NotesPasteboardReader.copy(text: note.content, imageData: store.imageData(for: note))
    }

    /// Header button: a new note from whatever the clipboard holds.
    func createFromClipboard() {
        switch NotesPasteboardReader.read() {
        case .image(let data): createNote(imageData: data)
        case .text(let text): createNote(content: text)
        case nil: break
        }
    }

    /// Command-V inside the tab. Returns true when the paste was taken over.
    ///
    /// A picture attaches to the open note, or starts a new one from the list. Text goes into
    /// a focused text field (title, body or search) as a normal paste; with no field focused it
    /// is appended to the open note's body, or starts a new note from the list.
    func handlePasteShortcut(textFieldHasFocus: Bool) -> Bool {
        if textFieldHasFocus, !NotesPasteboardReader.containsImage() {
            return false
        }
        guard let pasted = NotesPasteboardReader.read() else { return false }
        switch pasted {
        case .image(let data):
            if isEditing {
                withAnimation { setImage(data) }
            } else {
                withAnimation { createNote(imageData: data) }
            }
        case .text(let text):
            if isEditing {
                content.append(text)
            } else {
                createNote(content: text)
            }
        }
        return true
    }

    /// Makes the island's panel key so the editor receives typing without activating the app.
    func makeHostWindowKey() {
        guard let window = hostWindow, !window.isKeyWindow else { return }
        window.makeKey()
    }

    // MARK: - Private

    private func loadDraft(
        route newRoute: Route,
        title newTitle: String,
        content newContent: String,
        colorIndex newColor: Int,
        imageData newImageData: Data?,
        imageChange newChange: NoteImageChange
    ) {
        if isEditing { persist() }
        clearDraftTask?.cancel()
        autoSaveTask?.cancel()
        isLoadingDraft = true
        title = newTitle
        content = newContent
        colorIndex = newColor
        imageData = newImageData
        image = newImageData.flatMap(NSImage.init(data:))
        imageChange = newChange
        isLoadingDraft = false
        route = newRoute
        updateLayout()
    }

    private func closeEditor() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        route = .list
        updateLayout()
        clearDraftTask?.cancel()
        let delay = Self.draftClearDelay
        clearDraftTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isEditing else { return }
            self.isLoadingDraft = true
            self.title = ""
            self.content = ""
            self.colorIndex = 0
            self.imageData = nil
            self.image = nil
            self.imageChange = .unchanged
            self.isLoadingDraft = false
        }
    }

    private func draftDidChange() {
        guard !isLoadingDraft, isEditing else { return }
        autoSaveTask?.cancel()
        let delay = autoSaveDelay
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }
}
