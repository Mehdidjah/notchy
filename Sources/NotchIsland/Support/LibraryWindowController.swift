import AppKit
import SwiftUI

/// The SwiftUI content exists only while the window is open, so a closed library never
/// re-renders when the island's model changes.
@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private let model: NotchViewModel

    init(model: NotchViewModel) {
        self.model = model
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
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        if window?.contentView is NSHostingView<LibraryView> == false {
            window?.contentView = NSHostingView(rootView: LibraryView(model: model))
        }
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = NSView()
    }
}
