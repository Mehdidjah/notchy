import AppKit
import SwiftUI

/// Atoll-style settings window: 700 by 600, full-size content with a unified toolbar,
/// movable by its background. While it is open the app becomes a regular app with a Dock
/// icon and menu bar, as Atoll does, and returns to an accessory when it closes.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(model: NotchViewModel, settings: UserSettings, permissions: PermissionManager) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "NotchIsland Settings"
        window.identifier = NSUserInterfaceItemIdentifier("NotchIslandSettingsWindow")
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 700, height: 560)
        window.setFrameAutosaveName("NotchIsland.Settings")
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(model: model, settings: settings, permissions: permissions)
        )
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
