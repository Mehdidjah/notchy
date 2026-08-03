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
        panel.contentView = NSHostingView(
            rootView: QuickPasteView(model: model) { [weak panel] in panel?.orderOut(nil) }
        )
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        targetTracker.rememberFrontmostApplication()
        positionNearPointer()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.orderOut(nil)
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
