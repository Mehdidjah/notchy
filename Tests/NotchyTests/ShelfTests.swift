import Foundation
import Testing
@testable import Notchy

/// A throwaway folder for one test: shelf JSON, dropped files and a few sample files.
private struct ShelfSandbox {
    let root: URL
    let persistence: ShelfPersistence
    let temporaryFiles: ShelfTemporaryFileStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        persistence = ShelfPersistence(directory: root.appendingPathComponent("Shelf", isDirectory: true))
        temporaryFiles = ShelfTemporaryFileStore(rootDirectory: root.appendingPathComponent("Drops", isDirectory: true))
    }

    @MainActor
    func makeStore() -> ShelfStore {
        ShelfStore(persistence: persistence, temporaryFiles: temporaryFiles)
    }

    func sampleFile(_ name: String, contents: String = "hello") throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct ShelfTests {
    @Test
    func sameFileLinkOrTextIsShelvedOnce() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let file = try sandbox.sampleFile("report.pdf")
        let link = URL(string: "https://example.com/page")!

        let added = store.add([
            try ShelfItem.file(at: file),
            try ShelfItem.file(at: file),
            .link(link),
            .link(link),
            .text("note"),
            .text("note")
        ])

        #expect(added.count == 3)
        #expect(store.count == 3)
        #expect(store.add([try ShelfItem.file(at: file), .text("note")]).isEmpty)
        #expect(store.count == 3)
    }

    @Test
    func duplicateTemporaryTileNeverDeletesTheShelvedFile() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let first = try sandbox.temporaryFiles.writeText("same text")
        let firstItem = try ShelfItem.file(at: first, isTemporary: true)
        store.add([firstItem])

        // A second tile for the same temporary file is skipped, and the file it shares with
        // the shelved tile must survive.
        let duplicate = try ShelfItem.file(at: first, isTemporary: true)
        #expect(store.add([duplicate]).isEmpty)

        #expect(store.count == 1)
        #expect(FileManager.default.fileExists(atPath: first.path))

        store.remove(firstItem)
        #expect(store.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: first.path), "removing a temporary tile deletes its file")
    }

    @Test
    func itemsSurviveRelaunch() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let file = try sandbox.sampleFile("photo.png", contents: "png")
        let link = URL(string: "https://example.com")!
        let first = sandbox.makeStore()
        first.add([try ShelfItem.file(at: file), .link(link), .text("remember this")])
        let saved = first.items

        let second = sandbox.makeStore()

        #expect(second.items.map(\.id) == saved.map(\.id))
        #expect(second.items.map(\.kind) == saved.map(\.kind))
        #expect(second.items.first?.cachedPath == file.standardizedFileURL.path)
        #expect(second.items.first?.displayName == "photo.png")
        #expect(second.items.first?.fileURL?.standardizedFileURL == file.standardizedFileURL)
    }

    @Test
    func corruptEntriesAreSkippedOnLoad() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let good = ShelfItem.text("kept")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let goodJSON = String(decoding: try encoder.encode(good), as: UTF8.self)
        let payload = "[\(goodJSON), {\"id\": \"not-a-uuid\", \"kind\": {\"type\": \"mystery\"}}, 42]"
        try FileManager.default.createDirectory(
            at: sandbox.persistence.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(payload.utf8).write(to: sandbox.persistence.fileURL)

        let loaded = sandbox.persistence.load()

        #expect(loaded.map(\.id) == [good.id])
        #expect(loaded.first?.kind == .text("kept"))
    }

    @Test
    func clearRemovesEveryTileAndItsTemporaryFiles() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let dropped = try sandbox.temporaryFiles.write(data: Data([1, 2, 3]), preferredName: "Image.png")
        let kept = try sandbox.sampleFile("keep.txt")
        store.add([try ShelfItem.file(at: dropped, isTemporary: true), try ShelfItem.file(at: kept), .text("x")])
        store.select(store.items[0])

        store.clear()

        #expect(store.isEmpty)
        #expect(store.selectedIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dropped.path))
        #expect(FileManager.default.fileExists(atPath: kept.path), "files the user dropped are never deleted")
        #expect(sandbox.persistence.load().isEmpty)
    }

    @Test
    func pruneDropsDeletedFilesAndKeepsTheRest() async throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let doomed = try sandbox.sampleFile("doomed.txt")
        let survivor = try sandbox.sampleFile("survivor.txt")
        store.add([try ShelfItem.file(at: doomed), try ShelfItem.file(at: survivor), .text("text stays")])
        try FileManager.default.removeItem(at: doomed)

        await store.pruneMissingFiles()

        #expect(store.count == 2)
        #expect(store.items.contains { $0.cachedPath == survivor.standardizedFileURL.path })
        #expect(store.items.contains { $0.kind == .text("text stays") })
    }

    @Test
    func bookmarkFollowsARenamedFile() async throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let original = try sandbox.sampleFile("draft.txt")
        store.add([try ShelfItem.file(at: original)])
        let renamed = sandbox.root.appendingPathComponent("final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolved = await store.refreshedFileURL(for: store.items[0])

        #expect(resolved?.standardizedFileURL == renamed.standardizedFileURL)
        #expect(store.items[0].cachedPath == renamed.standardizedFileURL.path)
        #expect(store.items[0].displayName == "final.txt")
        #expect(store.items[0].identityKey == "file:" + renamed.standardizedFileURL.path)
    }

    @Test
    func selectionFollowsFinderConventions() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        store.add([.text("a"), .text("b"), .text("c"), .text("d")])
        let items = store.items

        store.select(items[0])
        store.extendSelection(to: items[2])
        #expect(store.selectedIDs == Set(items[0...2].map(\.id)))

        store.toggleSelection(items[1])
        #expect(store.selectedIDs == [items[0].id, items[2].id])

        store.moveSelection(by: 1)
        #expect(store.selectedIDs == [items[2].id], "arrow keys move from the last clicked tile")

        store.remove(items[2])
        #expect(store.selectedIDs.isEmpty, "removing the selected tile clears the selection")

        store.selectAll()
        #expect(store.selectedIDs.count == 3)
        store.removeSelected()
        #expect(store.isEmpty)
    }

    @Test
    func shareBundleWritesTextToAFileOnlyWhenAsked() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let store = sandbox.makeStore()
        let file = try sandbox.sampleFile("doc.txt")
        store.add([try ShelfItem.file(at: file), .text("plain words"), .link(URL(string: "https://example.com")!)])

        let asText = store.shareBundle(for: store.items, filesOnly: false)
        #expect(asText.objects.count == 3)
        #expect(asText.scratchURLs.isEmpty)
        #expect(asText.objects.contains { ($0 as? String) == "plain words" })

        let asFiles = store.shareBundle(for: store.items, filesOnly: true)
        #expect(asFiles.objects.count == 3)
        #expect(asFiles.scratchURLs.count == 1)
        let scratch = try #require(asFiles.scratchURLs.first)
        #expect(try String(contentsOf: scratch, encoding: .utf8) == "plain words")
        #expect(scratch.lastPathComponent == "plain words.txt")
        store.discardScratchFiles(asFiles.scratchURLs)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test
    func temporaryStoreNeverDeletesOutsideItsFolder() throws {
        let sandbox = try ShelfSandbox()
        defer { sandbox.tearDown() }
        let outside = try sandbox.sampleFile("outside.txt")

        sandbox.temporaryFiles.remove(outside)

        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(ShelfTemporaryFileStore.sanitizedFileName("a/b:c") == "a-b-c")
        #expect(ShelfTemporaryFileStore.sanitizedFileName("  ") == ShelfTemporaryFileStore.fallbackName)
        #expect(ShelfTemporaryFileStore.sanitizedFileName(".hidden") == ShelfTemporaryFileStore.fallbackName + ".hidden")
    }

    @Test
    func displayNamesAndIdentityKeys() throws {
        let link = ShelfItem.link(URL(string: "https://example.com/a?b=1")!)
        #expect(link.displayName == "example.com/a?b=1")
        #expect(link.identityKey == "link:https://example.com/a?b=1")
        #expect(link.openableURL == URL(string: "https://example.com/a?b=1"))

        let text = ShelfItem.text("  two words \n")
        #expect(text.displayName == "two words")
        #expect(text.identityKey == "text:  two words \n")
        #expect(text.openableURL == nil)
        #expect(text.fileURL == nil)

        #expect(throws: (any Error).self) {
            try ShelfItem.file(at: URL(fileURLWithPath: "/definitely/missing/\(UUID().uuidString)"))
        }
    }

    @Test
    func settingsDefaultsAndPersistence() {
        let suiteName = "ShelfTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ShelfSettings(defaults: defaults)
        #expect(settings.opensOnDrag)
        #expect(!settings.allowsMoveOnDragOut)
        #expect(!settings.removesAfterDragOut)
        #expect(settings.shareTarget == .airDrop)

        settings.allowsMoveOnDragOut = true
        settings.shareTarget = .shareMenu
        settings.opensOnDrag = false

        let reloaded = ShelfSettings(defaults: defaults)
        #expect(reloaded.allowsMoveOnDragOut)
        #expect(reloaded.shareTarget == .shareMenu)
        #expect(!reloaded.opensOnDrag)
        #expect(defaults.bool(forKey: "shelf.allowMoveOnDragOut"))
    }
}
