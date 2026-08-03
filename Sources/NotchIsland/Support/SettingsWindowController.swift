import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: NotchViewModel, settings: UserSettings, permissions: PermissionManager) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "NotchIsland Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(model: model, settings: settings, permissions: permissions)
        )
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
