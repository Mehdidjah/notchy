import AppKit

/// Whether Notchy is a regular app, with a Dock icon whose dot shows it is running and a place
/// in the app switcher, or only a menu-bar app. It is regular while "Show in the Dock" is on,
/// and otherwise only while one of its windows (Settings, the onboarding, the library) is open.
@MainActor
enum DockPresence {
    /// The "Show in the Dock" setting.
    static var isEnabled = true {
        didSet { update() }
    }

    /// Applies the policy. `closing` is a window that is about to close and no longer counts.
    static func update(closing: NSWindow? = nil) {
        let windowOpen = NSApp.windows.contains { window in
            window !== closing && window.isVisible && !(window is NSPanel) && window.styleMask.contains(.titled)
        }
        let policy: NSApplication.ActivationPolicy = isEnabled || windowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}

/// The menu bar Notchy shows while it is the active app: About, Settings, Hide and Quit, the
/// standard editing commands for text fields in its windows, and Minimize and Close.
@MainActor
enum AppMainMenu {
    static func install(openSettings: @escaping () -> Void) {
        let menu = make(openSettings: openSettings)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = menu.items.last?.submenu
    }

    static func make(openSettings: @escaping () -> Void) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Notchy")
        app.addItem(withTitle: "About Notchy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = ClosureMenuItem(title: "Settings…", keyEquivalent: ",", action: openSettings)
        app.addItem(settings)
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Notchy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Notchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}
