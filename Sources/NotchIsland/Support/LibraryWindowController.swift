import AppKit
import SwiftUI

@MainActor
final class LibraryWindowController: NSWindowController {
    init(model: NotchViewModel) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "NotchIsland Clipboard Library"
        window.minSize = CGSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NotchIsland.Library")
        window.contentView = NSHostingView(rootView: LibraryView(model: model))
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
