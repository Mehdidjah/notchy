import AppKit
import SwiftUI

@MainActor
final class QuickPasteWindowController: NSWindowController, NSWindowDelegate {
    private let model: NotchViewModel
    private let targetTracker: PasteTargetProviding

    init(model: NotchViewModel, targetTracker: PasteTargetProviding) {
        self.model = model
        self.targetTracker = targetTracker
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        panel.title = "Quick Paste"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = CGSize(width: 500, height: 420)
        panel.maxSize = CGSize(width: 640, height: 620)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }

    /// The SwiftUI content exists only while the panel is shown, so a hidden quick-paste view
    /// never re-renders when the island's model changes.
    private func installContent() {
        guard let panel = window, panel.contentView is NSHostingView<QuickPasteView> == false else { return }
        panel.contentView = NSHostingView(
            rootView: QuickPasteView(model: model) { [weak self] in self?.closeWindow() }
        )
    }

    private func removeContent() {
        window?.contentView = NSView()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        installContent()
        targetTracker.rememberFrontmostApplication()
        positionNearPointer()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.orderOut(nil)
        removeContent()
    }

    func windowWillClose(_ notification: Notification) {
        removeContent()
    }

    /// `hidesOnDeactivate` hides the panel when another app comes forward.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible == false else { return }
            self.removeContent()
        }
    }

    private func positionNearPointer() {
        guard let window else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        var origin = CGPoint(
            x: pointer.x - window.frame.width / 2,
            y: pointer.y - window.frame.height - 28
        )
        origin.x = min(max(visibleFrame.minX + 12, origin.x), visibleFrame.maxX - window.frame.width - 12)
        origin.y = min(max(visibleFrame.minY + 12, origin.y), visibleFrame.maxY - window.frame.height - 12)
        window.setFrameOrigin(origin)
    }
}
