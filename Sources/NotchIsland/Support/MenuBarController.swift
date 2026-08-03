import AppKit
import OSLog

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let logger = Logger(
        subsystem: "com.local.NotchIsland",
        category: "MenuBar"
    )

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let model: NotchViewModel
    private let openShelf: () -> Void
    private let openQuickPaste: () -> Void
    private let openLibrary: () -> Void
    private let openSettings: () -> Void

    init(
        model: NotchViewModel,
        openShelf: @escaping () -> Void,
        openQuickPaste: @escaping () -> Void,
        openLibrary: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.model = model
        self.openShelf = openShelf
        self.openQuickPaste = openQuickPaste
        self.openLibrary = openLibrary
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard.fill",
                accessibilityDescription: "NotchIsland"
            )
            button.image?.isTemplate = true
            button.title = " NotchIsland"
            button.toolTip = "NotchIsland Clipboard"
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        Self.logger.info("Menu bar item installed")
    }

    func stop() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(
            title: model.settings.captureEnabled ? "Saving Clipboard History" : "Clipboard Capture Paused",
            action: nil,
            keyEquivalent: ""
        )
        status.image = NSImage(
            systemSymbolName: model.settings.captureEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
            accessibilityDescription: nil
        )
        menu.addItem(status)
        menu.addItem(.separator())

        addItem("Open Notch Shelf", action: #selector(showShelf), keyEquivalent: "")
        addItem("Quick Paste…", action: #selector(showQuickPaste), keyEquivalent: "v", modifiers: [.control, .command])
        addItem("Open Clipboard Library", action: #selector(showLibrary), keyEquivalent: "l", modifiers: [.control, .command])
        menu.addItem(.separator())

        let captureTitle = model.settings.captureEnabled ? "Pause Capture" : "Resume Capture"
        addItem(captureTitle, action: #selector(toggleCapture), keyEquivalent: "")

        if !model.items.isEmpty {
            let recentMenu = NSMenu(title: "Recent Clips")
            for (index, clip) in model.items.prefix(10).enumerated() {
                let title = shortTitle(clip.title)
                let item = NSMenuItem(
                    title: "\(index == 9 ? 0 : index + 1). \(title)",
                    action: #selector(pasteRecent(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = clip.id.uuidString
                recentMenu.addItem(item)
            }
            let recentRoot = NSMenuItem(title: "Recent Clips", action: nil, keyEquivalent: "")
            recentRoot.submenu = recentMenu
            menu.addItem(recentRoot)
        }

        if model.queue.isActive {
            addItem(
                "Paste Next — \(model.queue.positionDescription)",
                action: #selector(pasteNextQueueItem),
                keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                modifiers: [.command]
            )
            addItem("Cancel Paste Queue", action: #selector(cancelQueue), keyEquivalent: "")
        } else if !model.selectedClips.isEmpty {
            addItem("Start Paste Queue", action: #selector(startQueue), keyEquivalent: "")
        }

        menu.addItem(.separator())
        addItem("Clear Non-Favorites", action: #selector(clearHistory), keyEquivalent: "")
        addItem("Settings…", action: #selector(showSettings), keyEquivalent: ",", modifiers: [.command])

        let updates = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
        updates.isEnabled = false
        updates.toolTip = "Available after the Sparkle feed is configured for distribution."
        menu.addItem(updates)

        menu.addItem(.separator())
        addItem("Quit NotchIsland", action: #selector(quit), keyEquivalent: "q", modifiers: [.command])
    }

    private func addItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    private func shortTitle(_ value: String) -> String {
        let flattened = value.replacingOccurrences(of: "\n", with: " ")
        return flattened.count <= 27 ? flattened : String(flattened.prefix(24)) + "…"
    }

    @objc private func showShelf() {
        Self.logger.info("Open Shelf selected")
        openShelf()
    }

    @objc private func showQuickPaste() {
        Self.logger.info("Quick Paste selected")
        openQuickPaste()
    }

    @objc private func showLibrary() {
        Self.logger.info("Library selected")
        openLibrary()
    }

    @objc private func showSettings() {
        Self.logger.info("Settings selected")
        openSettings()
    }

    @objc private func toggleCapture() { model.toggleCapture() }
    @objc private func startQueue() { model.startQueueMode() }
    @objc private func pasteNextQueueItem() { model.pasteNextQueueItem() }
    @objc private func cancelQueue() { model.cancelQueue() }
    @objc private func clearHistory() { model.clearHistoryPreservingProtected() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc
    private func pasteRecent(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value),
              let clip = model.items.first(where: { $0.id == id }) else { return }
        model.paste(clip)
    }
}
