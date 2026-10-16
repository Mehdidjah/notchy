import Combine
import Foundation

/// Pure merge of the island's notes with the Notes app's notes.
///
/// Rules: for linked pairs the newer modification date wins; a remote note carrying
/// an island marker links to that island note; other remote notes are imported in the first
/// colour; island notes whose remote copy disappeared are removed; island notes that are newer
/// than their remote copy are returned for pushing.
enum AppleNotesMerge {
    struct Result: Equatable {
        var notes: [NoteItem]
        /// Linked island notes that changed after their remote copy and must be written back.
        var notesToPush: [NoteItem]
    }

    static func merge(local: [NoteItem], remote: [RemoteAppleNote]) -> Result {
        // Notes can report the same identifier twice; keep the most recently modified copy.
        var remoteByID: [String: RemoteAppleNote] = [:]
        for note in remote {
            if let existing = remoteByID[note.id], existing.modificationDate >= note.modificationDate { continue }
            remoteByID[note.id] = note
        }

        var notes = local
        var linkedRemoteIDs = Set<String>()
        var pushIDs: [UUID] = []

        for index in notes.indices {
            guard let remoteID = notes[index].appleNotesID, let remoteNote = remoteByID[remoteID] else { continue }
            linkedRemoteIDs.insert(remoteID)
            if remoteNote.modificationDate > notes[index].modificationDate {
                apply(remoteNote, to: &notes[index])
            } else if notes[index].modificationDate > remoteNote.modificationDate {
                pushIDs.append(notes[index].id)
            }
        }

        let unlinked = remoteByID.values
            .filter { !linkedRemoteIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        for remoteNote in unlinked {
            if let linkedID = remoteNote.linkedNoteID,
               let index = notes.firstIndex(where: { $0.id == linkedID && $0.appleNotesID == nil }) {
                notes[index].appleNotesID = remoteNote.id
                linkedRemoteIDs.insert(remoteNote.id)
                if remoteNote.modificationDate > notes[index].modificationDate {
                    apply(remoteNote, to: &notes[index])
                }
                continue
            }
            notes.append(NoteItem(
                title: NoteItem.resolvedTitle(remoteNote.title),
                content: remoteNote.content,
                creationDate: remoteNote.creationDate,
                modificationDate: remoteNote.modificationDate,
                colorIndex: 0,
                appleNotesID: remoteNote.id
            ))
            linkedRemoteIDs.insert(remoteNote.id)
        }

        notes.removeAll { note in
            guard let remoteID = note.appleNotesID else { return false }
            return remoteByID[remoteID] == nil
        }

        let sorted = NoteOrdering.sorted(notes)
        let toPush = pushIDs.compactMap { id in sorted.first { $0.id == id } }
        return Result(notes: sorted, notesToPush: toPush)
    }

    private static func apply(_ remote: RemoteAppleNote, to note: inout NoteItem) {
        note.title = NoteItem.resolvedTitle(remote.title)
        note.content = remote.content
        note.creationDate = remote.creationDate
        note.modificationDate = remote.modificationDate
        note.appleNotesID = remote.id
    }
}

/// Optional two-way sync between the island's notes and the Notes app (off by default).
/// Island notes are written into a "Notchy" folder; Notes' notes are imported.
@MainActor
final class AppleNotesSyncManager: ObservableObject {
    static let shared = AppleNotesSyncManager()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private let store: NotesStore
    private let settings: NotesSettings
    private let scripting: any AppleNotesScripting
    private var syncTask: Task<Void, Never>?
    /// Island notes whose remote copy is being created; guards against creating it twice.
    private var pendingCreates: Set<UUID> = []
    /// Notes edited while their remote copy was being created; written once it exists.
    private var editedDuringCreate: Set<UUID> = []

    init(
        store: NotesStore = .shared,
        settings: NotesSettings = .shared,
        scripting: any AppleNotesScripting = OSAAppleNotesScripting()
    ) {
        self.store = store
        self.settings = settings
        self.scripting = scripting
    }

    var isEnabled: Bool { settings.appleNotesSyncEnabled }

    /// Starts a sync in the background unless one is running.
    func requestSync() {
        guard isEnabled, syncTask == nil else { return }
        syncTask = Task { [weak self] in
            await self?.sync()
            self?.syncTask = nil
        }
    }

    func cancel() {
        syncTask?.cancel()
        syncTask = nil
    }

    /// Fetches Notes, merges, writes the merge back, then pushes changed and unlinked notes.
    func sync() async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let remote = try await scripting.fetchNotes(scope: settings.appleNotesSyncScope)
            guard !Task.isCancelled, isEnabled else { return }
            // Merge against the library as it is now, so edits made during the fetch survive.
            store.loadIfNeeded()
            let result = AppleNotesMerge.merge(local: store.notes, remote: remote)
            store.replaceAll(with: result.notes)

            for note in result.notesToPush {
                guard !Task.isCancelled else { return }
                try await write(noteID: note.id)
            }
            let unlinked = store.notes.filter { $0.appleNotesID == nil && !pendingCreates.contains($0.id) }
            for note in unlinked {
                guard !Task.isCancelled else { return }
                try await write(noteID: note.id)
            }
            settings.appleNotesLastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Writes one island note to Notes after it was saved.
    func push(noteID: UUID) {
        guard isEnabled else { return }
        if pendingCreates.contains(noteID) {
            editedDuringCreate.insert(noteID)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.write(noteID: noteID)
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Deletes the Notes copy of a note removed from the island.
    func deleteRemote(of note: NoteItem) {
        guard isEnabled, let remoteID = note.appleNotesID else { return }
        Task { [weak self, scripting] in
            do {
                try await scripting.deleteNote(id: remoteID)
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    /// Creates or updates the remote copy of an island note.
    private func write(noteID: UUID) async throws {
        guard let note = store.note(id: noteID) else { return }
        let payload = AppleNotesPayload(noteID: note.id, title: note.title, content: note.content)

        if let remoteID = note.appleNotesID {
            if try await scripting.updateNote(id: remoteID, with: payload) { return }
            // The remote copy was deleted in Notes; recreate it below.
            store.setAppleNotesID(nil, for: noteID)
        }

        guard !pendingCreates.contains(noteID) else {
            editedDuringCreate.insert(noteID)
            return
        }
        pendingCreates.insert(noteID)
        defer { pendingCreates.remove(noteID) }
        let newID = try await scripting.createNote(payload)
        store.setAppleNotesID(newID, for: noteID)

        if editedDuringCreate.remove(noteID) != nil, let latest = store.note(id: noteID) {
            let refreshed = AppleNotesPayload(noteID: latest.id, title: latest.title, content: latest.content)
            _ = try await scripting.updateNote(id: newID, with: refreshed)
        }
    }
}
