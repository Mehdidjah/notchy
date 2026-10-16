import AppKit
import SwiftUI

/// Everything a tile can ask for: selection clicks, keyboard commands, drags out, the
/// context menu and its actions. One per shelf view; tiles hold it weakly.
@MainActor
final class ShelfInteractionHub: NSObject, ObservableObject {
    let store: ShelfStore
    let settings: ShelfSettings
    let quickLook: ShelfQuickLookController
    let sharing: ShelfSharingCoordinator

    /// Keeps the island open while a drag or a share sheet takes the pointer away.
    var holdOpen: (() -> Void)?
    var releaseHold: (() -> Void)?

    /// The tiles the open context menu acts on, and the tile view it was opened from.
    private var menuTargets: [ShelfItem] = []
    private weak var menuAnchorView: NSView?

    private enum MenuAction: Int {
        case open = 1, reveal, quickLook, share, copy, copyPath, remove, clear
    }

    init(
        store: ShelfStore,
        settings: ShelfSettings,
        quickLook: ShelfQuickLookController = .shared,
        sharing: ShelfSharingCoordinator = .shared
    ) {
        self.store = store
        self.settings = settings
        self.quickLook = quickLook
        self.sharing = sharing
    }

    var allowsMoveOnDragOut: Bool { settings.allowsMoveOnDragOut }

    // MARK: Pointer

    /// Plain click selects, shift extends, command toggles; a double-click opens the selection.
    func click(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags, clickCount: Int) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            store.extendSelection(to: item)
        } else if flags.contains(.command) {
            store.toggleSelection(item)
        } else if !store.isSelected(item.id) {
            store.select(item)
        }
        if clickCount == 2 {
            open(store.hasSelection ? store.selectedItems : [item])
        }
    }

    // MARK: Keyboard

    @discardableResult
    func handle(_ command: ShelfKeyCommand) -> Bool {
        switch command {
        case .quickLook:
            guard store.hasSelection else { return false }
            toggleQuickLook(store.selectedItems)
        case .open:
            guard store.hasSelection else { return false }
            open(store.selectedItems)
        case .remove:
            guard store.hasSelection else { return false }
            store.removeSelected()
        case .moveLeft:
            store.moveSelection(by: -1)
            refreshQuickLookIfPresented()
        case .moveRight:
            store.moveSelection(by: 1)
            refreshQuickLookIfPresented()
        case .selectAll:
            store.selectAll()
        case .escape:
            if quickLook.isPresented {
                quickLook.dismiss()
            } else if store.hasSelection {
                store.clearSelection()
            } else {
                return false
            }
        }
        return true
    }

    // MARK: Drag out

    /// A drag from a selected tile carries the whole selection; from any other tile, just it.
    func dragPayloads(for item: ShelfItem) -> [ShelfDragPayload] {
        if !store.isSelected(item.id) { store.select(item) }
        let selected = store.selectedItems
        let dragging = selected.count > 1 ? selected : [item]
        return dragging.compactMap { dragged in
            guard let writer = store.pasteboardWriter(for: dragged) else { return nil }
            return ShelfDragPayload(item: dragged, writer: writer, image: dragImage(for: dragged))
        }
    }

    func dragWillBegin() {
        store.beginDragOut()
        holdOpen?()
    }

    func dragEnded(_ operation: NSDragOperation, items: [ShelfItem]) {
        store.endDragOut()
        if !operation.isEmpty, settings.removesAfterDragOut {
            store.remove(ids: Set(items.map(\.id)))
        }
        releaseHold?()
    }

    // MARK: Actions

    func open(_ items: [ShelfItem]) {
        for item in items {
            switch item.kind {
            case .file, .link:
                if let url = item.openableURL { NSWorkspace.shared.open(url) }
            case .text(let string):
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(string, forType: .string)
            }
        }
    }

    func reveal(_ items: [ShelfItem]) {
        let urls = items.compactMap(\.fileURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func toggleQuickLook(_ items: [ShelfItem]) {
        let urls = store.previewURLs(for: items)
        guard !urls.isEmpty else { return }
        quickLook.toggle(urls: urls)
    }

    func refreshQuickLookIfPresented() {
        guard quickLook.isPresented else { return }
        quickLook.update(urls: store.previewURLs(for: store.selectedItems))
    }

    func share(_ items: [ShelfItem], from view: NSView?, via target: ShelfShareTarget? = nil) {
        let target = target ?? settings.shareTarget
        let bundle = store.shareBundle(for: items, filesOnly: target == .airDrop)
        guard !bundle.isEmpty else { return }
        let scratch = bundle.scratchURLs
        sharing.share(bundle.objects, via: target, from: view) { [weak store] in
            store?.discardScratchFiles(scratch)
        }
    }

    func copy(_ items: [ShelfItem]) {
        let writers = items.compactMap { store.pasteboardWriter(for: $0) }
        guard !writers.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(writers)
    }

    func copyPaths(_ items: [ShelfItem]) {
        let paths = items.compactMap { $0.fileURL?.path }
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func remove(_ items: [ShelfItem]) {
        store.remove(ids: Set(items.map(\.id)))
    }

    func clear() {
        if quickLook.isPresented { quickLook.dismiss() }
        store.clear()
    }

    // MARK: Context menu

    func showContextMenu(for item: ShelfItem, event: NSEvent, in view: NSView) {
        if !store.isSelected(item.id) { store.select(item) }
        let targets = store.selectedItems
        menuTargets = targets
        menuAnchorView = view
        let fileCount = targets.filter(\.isFile).count
        let openable = targets.filter { $0.openableURL != nil }.count
        let plural = targets.count > 1

        let menu = NSMenu()
        if openable > 0 {
            menu.addItem(menuItem("Open", .open))
        }
        if fileCount > 0 {
            menu.addItem(menuItem("Show in Finder", .reveal))
        }
        if openable > 0 {
            menu.addItem(menuItem("Quick Look", .quickLook, keyEquivalent: " "))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Share…", .share))
        menu.addItem(menuItem("Copy", .copy, keyEquivalent: "c"))
        if fileCount > 0 {
            menu.addItem(menuItem(plural ? "Copy Paths" : "Copy Path", .copyPath))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(plural ? "Remove \(targets.count) Items" : "Remove", .remove))
        if store.count > targets.count {
            menu.addItem(menuItem("Clear Shelf", .clear))
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func menuItem(_ title: String, _ action: MenuAction, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent == "c" ? [.command] : []
        item.target = self
        item.tag = action.rawValue
        return item
    }

    @objc
    private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = MenuAction(rawValue: sender.tag) else { return }
        let targets = menuTargets
        menuTargets = []
        switch action {
        case .open: open(targets)
        case .reveal: reveal(targets)
        case .quickLook: toggleQuickLook(targets)
        case .share: share(targets, from: menuAnchorView ?? anchorForSharing())
        case .copy: copy(targets)
        case .copyPath: copyPaths(targets)
        case .remove: remove(targets)
        case .clear: clear()
        }
    }

    /// The share picker needs a view in a window; the key window's content view does when no
    /// tile handed one over.
    private func anchorForSharing() -> NSView? {
        NSApp.keyWindow?.contentView ?? NSApp.windows.first { $0.isVisible }?.contentView
    }

    private func dragImage(for item: ShelfItem) -> NSImage {
        let thumbnail: NSImage
        switch item.kind {
        case .file:
            if let url = item.fileURL {
                thumbnail = ShelfThumbnailCache.shared.cachedThumbnail(for: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            } else {
                thumbnail = ShelfThumbnailCache.symbolCard(systemName: item.kind.symbolName)
            }
        case .text, .link:
            thumbnail = ShelfThumbnailCache.symbolCard(systemName: item.kind.symbolName)
        }
        let renderer = ImageRenderer(content: ShelfDragPreview(thumbnail: thumbnail, displayName: item.displayName))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? thumbnail
    }
}
