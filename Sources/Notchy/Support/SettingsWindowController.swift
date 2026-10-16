import AppKit
import SwiftUI

/// Atoll-style settings window: 700 by 600, full-size content with a unified toolbar,
/// movable by its background. While it is open the app becomes a regular app with a Dock
/// icon and menu bar, as Atoll does, and returns to an accessory when it closes.
///
/// The SwiftUI content exists only while the window is open: it observes the island's model,
/// so a hidden but live settings view would re-render on every tab switch and hover.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let makeContent: () -> NSView

    init(model: NotchViewModel, settings: UserSettings, permissions: PermissionManager) {
        makeContent = {
            NSHostingView(rootView: SettingsView(model: model, settings: settings, permissions: permissions))
        }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Notchy Settings"
        window.identifier = NSUserInterfaceItemIdentifier("NotchySettingsWindow")
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 700, height: 560)
        window.setFrameAutosaveName("Notchy.Settings")
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        if window?.contentView is NSHostingView<SettingsView> == false {
            window?.contentView = makeContent()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window?.contentView = NSView()
    }
}
