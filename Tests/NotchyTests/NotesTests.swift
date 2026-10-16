import AppKit
import Foundation
import Testing
@testable import Notchy

// MARK: - Helpers

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotesTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A clock the tests move forward by hand.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func makeStore(clock: TestClock, directory: URL = makeTemporaryDirectory()) -> NotesStore {
    NotesStore(directory: directory, now: { clock.now })
}

private func makeDefaults() -> UserDefaults {
    let name = "NotesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func pngData() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

/// In-memory stand-in for the Notes app.
private actor FakeAppleNotes: AppleNotesScripting {
    var remote: [RemoteAppleNote] = []
    var created: [AppleNotesPayload] = []
    var updated: [(String, AppleNotesPayload)] = []
    var deleted: [String] = []
    private var nextID = 1

    func seed(_ notes: [RemoteAppleNote]) { remote = notes }

    func fetchNotes(scope: AppleNotesSyncScope) async throws -> [RemoteAppleNote] { remote }

    func createNote(_ payload: AppleNotesPayload) async throws -> String {
        created.append(payload)
        defer { nextID += 1 }
        return "remote-\(nextID)"
    }

    func updateNote(id: String, with payload: AppleNotesPayload) async throws -> Bool {
        updated.append((id, payload))
        return true
    }

    func deleteNote(id: String) async throws { deleted.append(id) }

    func createdCount() -> Int { created.count }
    func updatedIDs() -> [String] { updated.map(\.0) }
    func deletedIDs() -> [String] { deleted }
}

// MARK: - Store

@MainActor
@Suite("Notes store")
struct NotesStoreTests {
    @Test func blankNewDraftIsNotSaved() {
        let store = makeStore(clock: TestClock())
        let result = store.save(id: UUID(), title: "  ", content: "", colorIndex: 0, image: .unchanged)
        #expect(result == nil)
        #expect(store.notes.isEmpty)
    }

    @Test func untitledDraftGetsDefaultTitle() {
        let store = makeStore(clock: TestClock())
        let result = store.save(id: UUID(), title: "", content: "Milk", colorIndex: 2, image: .unchanged)
        #expect(result?.wasCreated == true)
        #expect(store.notes.first?.title == "Untitled Note")
        #expect(store.notes.first?.colorIndex == 2)
    }

    @Test func pinnedFirstThenMostRecentlyModified() {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let a = UUID(), b = UUID(), c = UUID()
        store.save(id: a, title: "A", content: "", colorIndex: 0, image: .unchanged)
        clock.advance(10)
        store.save(id: b, title: "B", content: "", colorIndex: 0, image: .unchanged)
        clock.advance(10)
        store.save(id: c, title: "C", content: "", colorIndex: 0, image: .unchanged)
        #expect(store.notes.map(\.title) == ["C", "B", "A"])

        store.togglePin(id: a)
        #expect(store.notes.map(\.title) == ["A", "C", "B"])

        clock.advance(10)
        store.save(id: b, title: "B2", content: "", colorIndex: 0, image: .unchanged)
        #expect(store.notes.map(\.title) == ["A", "B2", "C"])
    }

    @Test func unchangedSaveKeepsModificationDate() {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let id = UUID()
        store.save(id: id, title: "T", content: "Body", colorIndex: 1, image: .unchanged)
        let first = store.note(id: id)!.modificationDate
        clock.advance(60)
        let result = store.save(id: id, title: "T", content: "Body", colorIndex: 1, image: .unchanged)
        #expect(result?.didChange == false)
        #expect(store.note(id: id)!.modificationDate == first)
    }

    @Test func searchMatchesTitleOrBodyAndColour() {
        let store = makeStore(clock: TestClock())
        store.save(id: UUID(), title: "Groceries", content: "eggs", colorIndex: 0, image: .unchanged)
        store.save(id: UUID(), title: "Work", content: "Ship the café build", colorIndex: 1, image: .unchanged)
        #expect(store.notes(matching: "GROC", colorIndex: nil).map(\.title) == ["Groceries"])
        #expect(store.notes(matching: "cafe", colorIndex: nil).map(\.title) == ["Work"])
        #expect(store.notes(matching: "", colorIndex: 1).map(\.title) == ["Work"])
        #expect(store.notes(matching: "eggs", colorIndex: 1).isEmpty)
    }

    @Test func persistsAndReloads() async {
        let clock = TestClock()
        let directory = makeTemporaryDirectory()
        let store = makeStore(clock: clock, directory: directory)
        let id = UUID()
        store.save(id: id, title: "Keep", content: "me", colorIndex: 4, image: .unchanged)
        store.togglePin(id: id)
        await store.flush()

        let reloaded = makeStore(clock: clock, directory: directory)
        reloaded.loadIfNeeded()
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.title == "Keep")
        #expect(reloaded.notes.first?.isPinned == true)
        #expect(reloaded.notes.first?.colorIndex == 4)
    }

    @Test func unreadableFileIsSetAside() throws {
        let directory = makeTemporaryDirectory()
        try Data("not json".utf8).write(to: directory.appendingPathComponent("notes.json"))
        let store = makeStore(clock: TestClock(), directory: directory)
        store.loadIfNeeded()
        #expect(store.notes.isEmpty)
        #expect(store.lastPersistenceError != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("notes.unreadable-") })
    }

    @Test func picturesAreWrittenAsPNGAndRemoved() async {
        let directory = makeTemporaryDirectory()
        let store = makeStore(clock: TestClock(), directory: directory)
        let id = UUID()
        store.save(id: id, title: "", content: "", colorIndex: 0, image: .replaced(pngData()))
        let note = try! #require(store.note(id: id))
        #expect(note.imageFileName == NoteItem.imageFileName(for: id))
        #expect(store.image(for: note) != nil)
        await store.flush()
        let file = store.imagesDirectory.appendingPathComponent(note.imageFileName!)
        #expect(FileManager.default.fileExists(atPath: file.path))

        store.save(id: id, title: "", content: "", colorIndex: 0, image: .removed)
        await store.flush()
        #expect(store.note(id: id)?.imageFileName == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deleteAndDeleteAll() {
        let store = makeStore(clock: TestClock())
        let a = UUID()
        store.save(id: a, title: "A", content: "", colorIndex: 0, image: .unchanged)
        store.save(id: UUID(), title: "B", content: "", colorIndex: 0, image: .unchanged)
        #expect(store.delete(id: a)?.title == "A")
        #expect(store.notes.count == 1)
        #expect(store.deleteAll().count == 1)
        #expect(store.isEmpty)
    }

    @Test func legacyRecordsDecodeWithDefaults() throws {
        let json = #"[{"id":"7C0D6C4E-6F7B-4E51-9D5A-0B3D1B0F4A11","title":"Old","content":"x","creationDate":"2024-01-01T00:00:00Z","colorIndex":3}]"#
        let notes = try NotesStore.decoder.decode([NoteItem].self, from: Data(json.utf8))
        #expect(notes.first?.modificationDate == notes.first?.creationDate)
        #expect(notes.first?.isPinned == false)
        #expect(notes.first?.color == NoteItem.palette[3])
    }
}

// MARK: - Presentation helpers

@Suite("Notes presentation")
struct NotesPresentationTests {
    @Test func timeAgoLabels() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(NoteOrdering.timeAgo(from: now.addingTimeInterval(-30), now: now) == "Just now")
        #expect(NoteOrdering.timeAgo(from: now.addingTimeInterval(-5 * 60), now: now) == "5m")
        #expect(NoteOrdering.timeAgo(from: now.addingTimeInterval(-3 * 3600), now: now) == "3h")
    }

    @Test func paletteFallsBackToYellow() {
        #expect(NoteItem.palette.count == 6)
        #expect(NoteItem.color(at: 99) == .yellow)
    }

    @MainActor @Test func layoutHeightsMatchDesign() {
        #expect(NotesLayoutMode.list.preferredHeight == 240)
        #expect(NotesLayoutMode.split.preferredHeight == 260)
        #expect(NotesLayoutMode.editor.preferredHeight == 320)
        let layout = NotesLayoutState()
        layout.setMode(.editor)
        #expect(layout.preferredHeight == 320)
        #expect(layout.extraHeight == 80)
        layout.setResting(showsClipboard: true)
        #expect(layout.mode == .split)
        #expect(layout.extraHeight == 20)
    }

    @MainActor @Test func settingsUseDesignDefaults() {
        let settings = NotesSettings(defaults: makeDefaults())
        #expect(settings.pinningEnabled)
        #expect(!settings.searchEnabled)
        #expect(!settings.colorFilteringEnabled)
        #expect(settings.createFromClipboardEnabled)
        #expect(settings.showsCharacterCount)
        #expect(!settings.appleNotesSyncEnabled)
        #expect(settings.appleNotesLastSyncDate == nil)
        #expect(!settings.showsSearchButton)
    }

    @MainActor @Test func settingsPersist() {
        let defaults = makeDefaults()
        let settings = NotesSettings(defaults: defaults)
        settings.searchEnabled = true
        settings.appleNotesSyncScope = .notchIslandFolder
        let reloaded = NotesSettings(defaults: defaults)
        #expect(reloaded.searchEnabled)
        #expect(reloaded.showsSearchButton)
        #expect(reloaded.appleNotesSyncScope == .notchIslandFolder)
    }
}

// MARK: - Apple Notes

@Suite("Apple Notes sync")
struct AppleNotesTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func remote(_ id: String, _ title: String, modified: TimeInterval, linked: UUID? = nil) -> RemoteAppleNote {
        RemoteAppleNote(
            id: id, title: title, content: "body \(title)",
            creationDate: base, modificationDate: base.addingTimeInterval(modified), linkedNoteID: linked
        )
    }

    @Test func newerSideWins() {
        let localNewer = NoteItem(title: "Local", content: "", creationDate: base, modificationDate: base.addingTimeInterval(100), appleNotesID: "r1")
        let remoteNewer = NoteItem(title: "Stale", content: "", creationDate: base, modificationDate: base, appleNotesID: "r2")
        let result = AppleNotesMerge.merge(
            local: [localNewer, remoteNewer],
            remote: [remote("r1", "Old remote", modified: 10), remote("r2", "Fresh", modified: 50)]
        )
        #expect(result.notesToPush.map(\.id) == [localNewer.id])
        let updated = result.notes.first { $0.id == remoteNewer.id }
        #expect(updated?.title == "Fresh")
        #expect(updated?.content == "body Fresh")
    }

    @Test func importsUnlinkedAndLinksMarkedNotes() {
        let local = NoteItem(title: "Mine", content: "", creationDate: base)
        let result = AppleNotesMerge.merge(
            local: [local],
            remote: [remote("r1", "Marked", modified: -10, linked: local.id), remote("r2", "", modified: 5)]
        )
        #expect(result.notes.count == 2)
        #expect(result.notes.first { $0.id == local.id }?.appleNotesID == "r1")
        #expect(result.notes.first { $0.id == local.id }?.title == "Mine")
        let imported = result.notes.first { $0.appleNotesID == "r2" }
        #expect(imported?.title == "Untitled Note")
        #expect(imported?.colorIndex == 0)
    }

    @Test func removesNotesDeletedInNotesAndDeduplicates() {
        let gone = NoteItem(title: "Gone", content: "", creationDate: base, appleNotesID: "missing")
        let localOnly = NoteItem(title: "Local only", content: "", creationDate: base)
        let result = AppleNotesMerge.merge(
            local: [gone, localOnly],
            remote: [remote("r1", "Old", modified: 1), remote("r1", "New", modified: 9)]
        )
        #expect(!result.notes.contains { $0.id == gone.id })
        #expect(result.notes.contains { $0.id == localOnly.id })
        #expect(result.notes.filter { $0.appleNotesID == "r1" }.map(\.title) == ["New"])
    }

    @Test func parsesScriptOutput() {
        let id = UUID()
        let f = String(OSAAppleNotesScripting.fieldSeparator)
        let r = String(OSAAppleNotesScripting.recordSeparator)
        let output = ["x-coredata://1", "Shopping", "2024-3-5-3600", "2024-3-6-7200", "Shopping\nEggs\nMilk", id.uuidString].joined(separator: f)
            + r + ["x-coredata://2", "Bad", "nope", "2024-1-1-0", "", ""].joined(separator: f)
        let utc = TimeZone(identifier: "UTC")!
        let notes = OSAAppleNotesScripting.parseRecords(output, timeZone: utc)
        #expect(notes.count == 1)
        #expect(notes.first?.content == "Eggs\nMilk")
        #expect(notes.first?.linkedNoteID == id)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let expected = calendar.date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 1))
        #expect(notes.first?.creationDate == expected)
    }

    @Test func scriptLiteralsAndBodyAreEscaped() {
        #expect(OSAAppleNotesScripting.literal("a \"b\" \\ c\nd") == #""a \"b\" \\ c\nd""#)
        let id = UUID()
        let html = OSAAppleNotesScripting.htmlBody(for: AppleNotesPayload(noteID: id, title: "<T>", content: "x & y\n\nz"))
        #expect(html == "<div><h1>&lt;T&gt;</h1></div><div>x &amp; y</div><div><br></div><div>z</div><!--notchisland:id=\(id.uuidString)-->")
    }

    @MainActor @Test func syncMergesPushesAndLinks() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let defaults = makeDefaults()
        let settings = NotesSettings(defaults: defaults)
        settings.appleNotesSyncEnabled = true
        let fake = FakeAppleNotes()
        await fake.seed([remote("r9", "From Notes", modified: 0)])
        let sync = AppleNotesSyncManager(store: store, settings: settings, scripting: fake)

        store.save(id: UUID(), title: "Island", content: "x", colorIndex: 1, image: .unchanged)
        await sync.sync()

        #expect(store.notes.count == 2)
        #expect(store.notes.allSatisfy { $0.appleNotesID != nil })
        #expect(await fake.createdCount() == 1)
        #expect(settings.appleNotesLastSyncDate != nil)
        #expect(sync.lastError == nil)

        let removed = store.notes.first { $0.appleNotesID == "r9" }!
        sync.deleteRemote(of: removed)
        for _ in 0..<50 where await fake.deletedIDs().isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fake.deletedIDs() == ["r9"])
    }

    @MainActor @Test func syncDoesNothingWhenDisabled() async {
        let store = makeStore(clock: TestClock())
        let settings = NotesSettings(defaults: makeDefaults())
        let fake = FakeAppleNotes()
        await fake.seed([remote("r1", "Remote", modified: 0)])
        let sync = AppleNotesSyncManager(store: store, settings: settings, scripting: fake)
        await sync.sync()
        #expect(store.notes.isEmpty)
    }
}

// MARK: - Tab controller

@MainActor
@Suite("Notes tab controller")
struct NotesTabControllerTests {
    private func makeController(store: NotesStore, delay: Duration = .milliseconds(30)) -> NotesTabController {
        let settings = NotesSettings(defaults: makeDefaults())
        return NotesTabController(
            store: store,
            settings: settings,
            layout: NotesLayoutState(),
            sync: AppleNotesSyncManager(store: store, settings: settings, scripting: FakeAppleNotes()),
            autoSaveDelay: delay
        )
    }

    @Test func editorRaisesLayoutAndAutoSaves() async {
        let store = makeStore(clock: TestClock())
        let controller = makeController(store: store)
        controller.createNote()
        #expect(controller.isEditingNewNote)
        #expect(controller.layout.mode == .editor)

        controller.content = "Typed"
        #expect(store.notes.isEmpty)
        for _ in 0..<50 where store.notes.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.notes.first?.content == "Typed")
        #expect(store.notes.first?.title == "Untitled Note")

        controller.done()
        #expect(!controller.isEditing)
        #expect(controller.layout.mode == .list)
    }

    @Test func blankNewNoteIsDiscardedOnBack() {
        let store = makeStore(clock: TestClock())
        let controller = makeController(store: store)
        controller.createNote()
        controller.back()
        #expect(store.notes.isEmpty)
        #expect(controller.route == .list)
    }

    @Test func openingANoteDoesNotTouchIt() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let id = UUID()
        store.save(id: id, title: "Keep", content: "Body", colorIndex: 2, image: .unchanged)
        let before = store.note(id: id)!.modificationDate
        clock.advance(120)

        let controller = makeController(store: store)
        controller.open(store.note(id: id)!)
        #expect(controller.title == "Keep")
        #expect(controller.colorIndex == 2)
        try? await Task.sleep(for: .milliseconds(80))
        controller.back()
        #expect(store.note(id: id)!.modificationDate == before)
    }

    @Test func colourChangeIsSaved() {
        let store = makeStore(clock: TestClock())
        let id = UUID()
        store.save(id: id, title: "Note", content: "", colorIndex: 0, image: .unchanged)
        let controller = makeController(store: store, delay: .seconds(60))
        controller.open(store.note(id: id)!)
        controller.colorIndex = 5
        controller.done()
        #expect(store.note(id: id)?.colorIndex == 5)
    }
}

// MARK: - Parity review additions

@MainActor
@Suite("Notes pictures and keyboard")
struct NotesPictureAndKeyboardTests {
    @Test func savedPictureLoadsInBackgroundAfterReload() async {
        let directory = makeTemporaryDirectory()
        let clock = TestClock()
        let store = makeStore(clock: clock, directory: directory)
        let id = UUID()
        store.save(id: id, title: "Pic", content: "", colorIndex: 0, image: .replaced(pngData()))
        await store.flush()

        let reloaded = makeStore(clock: clock, directory: directory)
        reloaded.loadIfNeeded()
        let note = try! #require(reloaded.note(id: id))
        // The first request only starts the read; the row redraws once it lands.
        #expect(reloaded.image(for: note) == nil)
        for _ in 0..<100 where reloaded.imageRevision == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(reloaded.imageRevision == 1)
        #expect(reloaded.image(for: note) != nil)
    }

    @Test func missingPictureIsNotRetried() async {
        let store = makeStore(clock: TestClock())
        let note = NoteItem(title: "Gone", content: "", imageFileName: "note_image_missing.png")
        #expect(store.image(for: note) == nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(store.image(for: note) == nil)
        #expect(store.imageRevision == 0)
    }

    @Test func pictureDataIsReadAfterQueuedWrites() {
        let store = makeStore(clock: TestClock())
        let id = UUID()
        let data = pngData()
        store.save(id: id, title: "", content: "", colorIndex: 0, image: .replaced(data))
        let note = try! #require(store.note(id: id))
        // No flush: the read waits for the queued PNG write.
        let read = store.imageData(for: note)
        #expect(read != nil)
        #expect(NSImage(data: read ?? Data()) != nil)
    }

    @Test func editingShortcutsMapToTextActions() {
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "c", shift: false) == #selector(NSText.copy(_:)))
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "x", shift: false) == #selector(NSText.cut(_:)))
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "a", shift: false) == #selector(NSText.selectAll(_:)))
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "z", shift: false) == Selector(("undo:")))
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "z", shift: true) == Selector(("redo:")))
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "q", shift: false) == nil)
        #expect(NotesKeyboardBridgeView.editingAction(forKey: "c", shift: true) == nil)
    }

    @Test func settingsPaneBuildsWithAndWithoutHostToggle() {
        // Builds the pane the Settings window shows, with and without the host toggle.
        _ = NotesSettingsSection(settings: NotesSettings(defaults: makeDefaults())).body
        _ = NotesSettingsPane(userSettings: UserSettings(defaults: makeDefaults())).body
    }
}
