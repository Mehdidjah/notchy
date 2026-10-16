import AppKit
import Combine
import Foundation

/// What a save does to a note's picture.
enum NoteImageChange: Equatable, Sendable {
    case unchanged
    case removed
    case replaced(Data)
}

/// Outcome of saving an editor draft.
struct NoteSaveResult: Equatable, Sendable {
    let note: NoteItem
    let wasCreated: Bool
    let didChange: Bool
}

/// The local notes library: notes kept in memory in display order and written as JSON to
/// `Application Support/NotchIsland/Notes/notes.json`, pictures as PNGs in `Images/` beside it.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    /// All notes, pinned first and then most recently modified.
    @Published private(set) var notes: [NoteItem] = []
    @Published private(set) var lastPersistenceError: String?
    /// Bumped when a picture finishes loading in the background, so the list redraws its rows.
    @Published private(set) var imageRevision = 0

    let directory: URL
    private let disk: NotesDiskWriter
    private let now: () -> Date
    private var hasLoaded = false
    private var imageCache: [String: NSImage] = [:]
    /// Pictures being read off the main thread, with a token so a stale read never replaces a
    /// picture saved or removed in the meantime.
    private var pendingImageLoads: [String: UUID] = [:]
    /// Pictures that could not be read, so redraws do not keep retrying them.
    private var unreadableImages: Set<String> = []

    init(directory: URL = NotesStore.defaultDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
        disk = NotesDiskWriter()
    }

    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("NotchIsland", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
    }

    var notesFileURL: URL { directory.appendingPathComponent("notes.json") }
    var imagesDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    // MARK: - Loading

    /// Reads the library once. The file is small, so it is read in place.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        reload()
    }

    func reload() {
        hasLoaded = true
        imageCache.removeAll()
        pendingImageLoads.removeAll()
        unreadableImages.removeAll()
        let url = notesFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            notes = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            notes = NoteOrdering.sorted(try Self.decoder.decode([NoteItem].self, from: data))
            lastPersistenceError = nil
        } catch {
            // Keep an unreadable file aside instead of overwriting it with an empty library.
            let stamp = Int(now().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("notes.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            notes = []
            lastPersistenceError = error.localizedDescription
        }
    }

    // MARK: - Queries

    var isEmpty: Bool { notes.isEmpty }

    func note(id: UUID) -> NoteItem? {
        notes.first { $0.id == id }
    }

    func notes(matching query: String, colorIndex: Int?) -> [NoteItem] {
        NoteOrdering.filtered(notes, query: query, colorIndex: colorIndex)
    }

    // MARK: - Editing

    /// Creates or updates a note from an editor draft. A brand-new draft with no title, body or
    /// picture is not saved. An existing note keeps its modification date when nothing changed.
    @discardableResult
    func save(
        id: UUID,
        title: String,
        content: String,
        colorIndex: Int,
        image: NoteImageChange
    ) -> NoteSaveResult? {
        loadIfNeeded()
        let storedTitle = NoteItem.resolvedTitle(title)
        let index = notes.firstIndex { $0.id == id }

        guard let index else {
            let hasImage = if case .replaced = image { true } else { false }
            let isBlank = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && content.isEmpty
                && !hasImage
            guard !isBlank else { return nil }
            let timestamp = now()
            var note = NoteItem(
                id: id,
                title: storedTitle,
                content: content,
                creationDate: timestamp,
                modificationDate: timestamp,
                colorIndex: colorIndex
            )
            if case .replaced(let data) = image {
                note.imageFileName = storeImage(data, for: id)
            }
            notes.insert(note, at: 0)
            commit()
            return NoteSaveResult(note: note, wasCreated: true, didChange: true)
        }

        var note = notes[index]
        var changed = note.title != storedTitle || note.content != content || note.colorIndex != colorIndex
        switch image {
        case .unchanged:
            break
        case .removed:
            if let name = note.imageFileName {
                removeImageFile(named: name)
                note.imageFileName = nil
                changed = true
            }
        case .replaced(let data):
            note.imageFileName = storeImage(data, for: id)
            changed = true
        }
        guard changed else {
            return NoteSaveResult(note: note, wasCreated: false, didChange: false)
        }
        note.title = storedTitle
        note.content = content
        note.colorIndex = colorIndex
        note.modificationDate = now()
        notes[index] = note
        commit()
        return NoteSaveResult(note: note, wasCreated: false, didChange: true)
    }

    func togglePin(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        commit()
    }

    /// Removes a note and its picture; returns the removed note so a linked remote copy can go too.
    @discardableResult
    func delete(id: UUID) -> NoteItem? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = notes.remove(at: index)
        if let name = removed.imageFileName { removeImageFile(named: name) }
        commit()
        return removed
    }

    /// Removes every note and picture; returns what was removed.
    @discardableResult
    func deleteAll() -> [NoteItem] {
        let removed = notes
        notes.removeAll()
        imageCache.removeAll()
        pendingImageLoads.removeAll()
        unreadableImages.removeAll()
        disk.removeItem(at: imagesDirectory)
        commit()
        return removed
    }

    func setAppleNotesID(_ appleNotesID: String?, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].appleNotesID != appleNotesID else { return }
        notes[index].appleNotesID = appleNotesID
        commit()
    }

    /// Replaces the library with a merged copy (Apple Notes sync). Pictures of notes that are
    /// no longer present are deleted.
    func replaceAll(with merged: [NoteItem]) {
        let keptIDs = Set(merged.map(\.id))
        for note in notes where !keptIDs.contains(note.id) {
            if let name = note.imageFileName { removeImageFile(named: name) }
        }
        notes = merged
        commit()
    }

    // MARK: - Pictures

    /// The note's picture for a list row. A picture not yet in memory is read in the
    /// background; the row redraws through `imageRevision` once it is ready.
    func image(for note: NoteItem) -> NSImage? {
        guard let name = note.imageFileName else { return nil }
        if let cached = imageCache[name] { return cached }
        loadImageInBackground(named: name)
        return nil
    }

    /// The picture's bytes, for the editor and for copying the note. Read in order with the
    /// queued writes, so a picture saved a moment ago is never read in its previous version.
    func imageData(for note: NoteItem) -> Data? {
        guard let name = note.imageFileName else { return nil }
        if let data = disk.read(imagesDirectory.appendingPathComponent(name)) { return data }
        return imageCache[name]?.tiffRepresentation
    }

    /// Waits until every queued write has reached the disk.
    func flush() async {
        await disk.flush()
    }

    /// Blocks until every queued write has reached the disk; used while the app shuts down.
    func flushSynchronously() {
        disk.flushSynchronously()
    }

    // MARK: - Private

    private func commit() {
        notes = NoteOrdering.sorted(notes)
        let snapshot = notes
        let url = notesFileURL
        disk.write(notes: snapshot, to: url) { [weak self] message in
            Task { @MainActor in self?.lastPersistenceError = message }
        }
    }

    private func loadImageInBackground(named name: String) {
        guard pendingImageLoads[name] == nil, !unreadableImages.contains(name) else { return }
        let token = UUID()
        pendingImageLoads[name] = token
        let url = imagesDirectory.appendingPathComponent(name)
        Task { [weak self] in
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard let self, self.pendingImageLoads[name] == token else { return }
            self.pendingImageLoads[name] = nil
            guard let data, let image = NSImage(data: data) else {
                self.unreadableImages.insert(name)
                return
            }
            self.imageCache[name] = image
            self.imageRevision &+= 1
        }
    }

    private func storeImage(_ data: Data, for id: UUID) -> String {
        let name = NoteItem.imageFileName(for: id)
        pendingImageLoads[name] = nil
        unreadableImages.remove(name)
        if let image = NSImage(data: data) {
            imageCache[name] = image
        } else {
            imageCache.removeValue(forKey: name)
        }
        disk.writeImage(data, to: imagesDirectory.appendingPathComponent(name))
        return name
    }

    private func removeImageFile(named name: String) {
        imageCache.removeValue(forKey: name)
        pendingImageLoads[name] = nil
        disk.removeItem(at: imagesDirectory.appendingPathComponent(name))
    }

    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Writes notes and pictures on a serial background queue so the order of writes is kept and
/// the main thread never waits on the disk.
final class NotesDiskWriter: Sendable {
    private let queue = DispatchQueue(label: "NotchIsland.notes.disk", qos: .utility)

    func write(notes: [NoteItem], to url: URL, onError: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(notes)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                onError(nil)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    /// Stores the picture as PNG whatever format it arrived in.
    func writeImage(_ data: Data, to url: URL) {
        queue.async {
            let png = Self.pngData(from: data) ?? data
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? png.write(to: url, options: .atomic)
        }
    }

    func removeItem(at url: URL) {
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    func flushSynchronously() {
        queue.sync {}
    }

    /// Reads a file after every write queued before it.
    func read(_ url: URL) -> Data? {
        queue.sync { try? Data(contentsOf: url) }
    }

    static func pngData(from data: Data) -> Data? {
        if let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        guard let tiff = NSImage(data: data)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
