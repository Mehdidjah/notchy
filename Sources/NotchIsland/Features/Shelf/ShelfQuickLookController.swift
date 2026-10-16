import AppKit
import QuickLookUI

/// The list the Quick Look panel reads. Immutable: a new one is made whenever the URLs change,
/// so the panel never sees a list mutate under it.
final class ShelfQuickLookItems: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

/// Drives the shared Quick Look panel for shelf tiles: Space or a double-click opens it on
/// the selection, and the selection changing while it is up swaps what it shows.
@MainActor
final class ShelfQuickLookController {
    static let shared = ShelfQuickLookController()

    private(set) var isPresented = false
    private var dataSource: ShelfQuickLookItems?
    private var closeObserver: NSObjectProtocol?

    func toggle(urls: [URL]) {
        if isPresented {
            dismiss()
        } else {
            present(urls: urls)
        }
    }

    func present(urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        dataSource = ShelfQuickLookItems(urls: urls)
        attach(to: panel)
        isPresented = true
        observeClose(of: panel)
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Shows a new set without closing the panel. No-op while the panel is down.
    func update(urls: [URL]) {
        guard isPresented, !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        dataSource = ShelfQuickLookItems(urls: urls)
        attach(to: panel)
        panel.reloadData()
    }

    func dismiss() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else {
            isPresented = false
            return
        }
        if panel.isVisible { panel.orderOut(nil) }
        detach(from: panel)
        isPresented = false
    }

    /// Responder-chain hook: a view that accepts panel control hands the panel our list.
    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = dataSource
        panel.delegate = dataSource
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === dataSource { panel.dataSource = nil }
        if panel.delegate === dataSource { panel.delegate = nil }
    }

    private func observeClose(of panel: QLPreviewPanel) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ShelfQuickLookController.shared.isPresented = false
            }
        }
    }
}
