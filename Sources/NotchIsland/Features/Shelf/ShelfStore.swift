import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Objects handed to a sharing service, plus any scratch files that should be deleted once
/// the share has finished.
struct ShelfShareBundle {
    var objects: [Any]
    var scratchURLs: [URL]

    var isEmpty: Bool { objects.isEmpty }
}

/// The shelf: dropped items, their selection, and the JSON file that keeps them between
/// launches.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore.production()

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedIDs: Set<ShelfItem.ID> = []
    /// True while dropped providers are being read; a drop of large images takes a moment.
    @Published private(set) var isImporting = false
    /// True while a tile is being dragged out to another app.
    @Published private(set) var isDraggingOut = false
    @Published private(set) var lastErrorDescription: String?

    let importer: ShelfDropImporter
    let temporaryFiles: ShelfTemporaryFileStore
    private let persistence: ShelfPersistence?
    /// The tile a shift-click extends from.
    private var selectionAnchorID: ShelfItem.ID?
    private var pendingImports = 0

    init(persistence: ShelfPersistence?, temporaryFiles: ShelfTemporaryFileStore) {
        self.persistence = persistence
        self.temporaryFiles = temporaryFiles
        importer = ShelfDropImporter(temporaryFiles: temporaryFiles)
        items = persistence?.load() ?? []
    }

    static func production() -> ShelfStore {
        let persistence = try? ShelfPersistence.production()
        let temporaryFiles = (try? ShelfTemporaryFileStore.production())
            ?? ShelfTemporaryFileStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("NotchIsland-ShelfDrops", isDirectory: true)
            )
        return ShelfStore(persistence: persistence, temporaryFiles: temporaryFiles)
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var hasSelection: Bool { !selectedIDs.isEmpty }

    var selectedItems: [ShelfItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    func item(withID id: ShelfItem.ID) -> ShelfItem? {
        items.first { $0.id == id }
    }

    // MARK: Adding and removing

    /// Appends what is new and returns it. A drop that repeats something already on the shelf
    /// adds nothing and touches no file: a duplicate file tile points at the very file the
    /// shelved tile uses.
    @discardableResult
    func add(_ newItems: [ShelfItem]) -> [ShelfItem] {
        guard !newItems.isEmpty else { return [] }
        var seen = Set(items.map(\.identityKey))
        var added: [ShelfItem] = []
        for item in newItems where seen.insert(item.identityKey).inserted {
            added.append(item)
        }
        guard !added.isEmpty else { return [] }
        commit(items + added)
        return added
    }

    func remove(_ item: ShelfItem) {
        remove(ids: [item.id])
    }

    func remove(ids: Set<ShelfItem.ID>) {
        guard !ids.isEmpty else { return }
        let leaving = items.filter { ids.contains($0.id) }
        guard !leaving.isEmpty else { return }
        for item in leaving { discardStoredData(for: item) }
        commit(items.filter { !ids.contains($0.id) })
    }

    func removeSelected() {
        remove(ids: selectedIDs)
    }

    func clear() {
        guard !items.isEmpty else { return }
        for item in items { discardStoredData(for: item) }
        commit([])
    }

    /// Reads the providers off the main actor, then adds the result.
    func importProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        pendingImports += 1
        isImporting = true
        let importer = self.importer
        let dropped = ShelfDroppedProviders(providers)
        Task { [weak self] in
            let imported = await importer.items(from: dropped)
            guard let self else { return }
            self.add(imported)
            self.pendingImports -= 1
            if self.pendingImports == 0 { self.isImporting = false }
        }
    }

    func importFileURLs(_ urls: [URL]) {
        add(importer.items(from: urls))
    }

    /// Drops tiles whose file has gone and refreshes paths of files that moved.
    func pruneMissingFiles() async {
        let snapshot = items
        var missing: Set<ShelfItem.ID> = []
        var moved: [ShelfItem.ID: ShelfBookmark.Resolution] = [:]
        for item in snapshot {
            guard case .file(let data) = item.kind else { continue }
            let bookmark = ShelfBookmark(data: data)
            guard let resolution = await bookmark.resolveInBackground(),
                  await bookmark.fileExists() else {
                missing.insert(item.id)
                continue
            }
            if resolution.url.standardizedFileURL.path != item.cachedPath || resolution.refreshedData != nil {
                moved[item.id] = resolution
            }
        }
        guard !missing.isEmpty || !moved.isEmpty else { return }
        var updated = items
        for index in updated.indices {
            guard let resolution = moved[updated[index].id] else { continue }
            applyResolution(resolution, to: &updated[index])
        }
        updated.removeAll { missing.contains($0.id) }
        commit(updated)
    }

    /// The file behind a tile, following it if it has been renamed or moved since it was
    /// added. The cached path is updated so later lookups are instant.
    func refreshedFileURL(for item: ShelfItem) async -> URL? {
        guard case .file(let data) = item.kind else { return nil }
        guard let resolution = await ShelfBookmark(data: data).resolveInBackground() else { return item.fileURL }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              items[index].kind == item.kind else { return resolution.url }
        if resolution.url.standardizedFileURL.path != items[index].cachedPath || resolution.refreshedData != nil {
            var updated = items
            applyResolution(resolution, to: &updated[index])
            commit(updated)
        }
        return resolution.url
    }

    // MARK: Selection

    func isSelected(_ id: ShelfItem.ID) -> Bool {
        selectedIDs.contains(id)
    }

    func select(_ item: ShelfItem) {
        selectedIDs = [item.id]
        selectionAnchorID = item.id
    }

    func toggleSelection(_ item: ShelfItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        selectionAnchorID = item.id
    }

    /// Shift-click: everything between the anchor and this tile.
    func extendSelection(to item: ShelfItem) {
        let anchorID = selectionAnchorID ?? selectedIDs.first ?? item.id
        guard let start = items.firstIndex(where: { $0.id == anchorID }),
              let end = items.firstIndex(where: { $0.id == item.id }) else {
            select(item)
            return
        }
        selectedIDs = Set(items[min(start, end)...max(start, end)].map(\.id))
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
        if selectionAnchorID.map({ id in selectedIDs.contains(id) }) != true {
            selectionAnchorID = items.first?.id
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        selectionAnchorID = nil
    }

    /// Arrow keys: moves a single selection along the row, or starts one at the first tile.
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = selectionAnchorID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? selectedItems.first.flatMap { item in items.firstIndex { $0.id == item.id } }
        let next: Int
        if let currentIndex {
            next = min(max(0, currentIndex + delta), items.count - 1)
        } else {
            next = delta >= 0 ? 0 : items.count - 1
        }
        select(items[next])
    }

    func beginDragOut() {
        isDraggingOut = true
    }

    func endDragOut() {
        isDraggingOut = false
    }

    // MARK: Payloads

    /// What a tile writes onto a drag or copy pasteboard.
    func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting? {
        switch item.kind {
        case .file: item.fileURL.map { $0 as NSURL }
        case .text(let string): string as NSString
        case .link(let url): url as NSURL
        }
    }

    /// Files first, then links; text tiles have nothing Quick Look can show.
    func previewURLs(for items: [ShelfItem]) -> [URL] {
        items.compactMap(\.openableURL)
    }

    /// Items for a share sheet. Text is shared as text unless `filesOnly` asks for a file, as
    /// AirDrop does; the scratch file is reported so the caller can delete it afterwards.
    func shareBundle(for items: [ShelfItem], filesOnly: Bool) -> ShelfShareBundle {
        var bundle = ShelfShareBundle(objects: [], scratchURLs: [])
        for item in items {
            switch item.kind {
            case .file:
                if let url = item.fileURL { bundle.objects.append(url) }
            case .link(let url):
                bundle.objects.append(url)
            case .text(let string):
                if filesOnly {
                    if let url = try? temporaryFiles.writeText(string) {
                        bundle.objects.append(url)
                        bundle.scratchURLs.append(url)
                    }
                } else {
                    bundle.objects.append(string)
                }
            }
        }
        return bundle
    }

    func discardScratchFiles(_ urls: [URL]) {
        for url in urls { temporaryFiles.remove(url) }
    }

    // MARK: Private

    private func commit(_ newItems: [ShelfItem]) {
        items = newItems
        let valid = Set(newItems.map(\.id))
        if !selectedIDs.isSubset(of: valid) { selectedIDs.formIntersection(valid) }
        if let anchor = selectionAnchorID, !valid.contains(anchor) { selectionAnchorID = selectedIDs.first }
        guard let persistence else { return }
        do {
            try persistence.save(newItems)
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    private func discardStoredData(for item: ShelfItem) {
        guard item.isTemporary, let url = item.fileURL else { return }
        temporaryFiles.remove(url)
        ShelfThumbnailCache.shared.invalidate(url)
    }

    private func applyResolution(_ resolution: ShelfBookmark.Resolution, to item: inout ShelfItem) {
        if let refreshed = resolution.refreshedData {
            item.kind = .file(bookmark: refreshed)
        }
        let url = resolution.url.standardizedFileURL
        item.cachedPath = url.path
        item.cachedDisplayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? url.lastPathComponent
    }
}

extension ShelfItem {
    /// For hosts that drag with SwiftUI's `onDrag`: files travel as file URLs, links as URLs,
    /// text as text.
    func dragItemProvider() -> NSItemProvider {
        switch kind {
        case .file:
            if let url = fileURL, let provider = NSItemProvider(contentsOf: url) {
                provider.suggestedName = displayName
                return provider
            }
            return NSItemProvider(object: displayName as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .text(let string):
            return NSItemProvider(object: string as NSString)
        }
    }
}
