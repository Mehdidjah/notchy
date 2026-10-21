import AppKit
import Testing
@testable import Notchy

@MainActor
struct DockPresenceTests {
    @Test func notchyIsInTheDockByDefault() {
        let suite = "DockPresenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserSettings(defaults: defaults)
        #expect(settings.showInDock)
        settings.showInDock = false
        #expect(UserSettings(defaults: defaults).showInDock == false)
    }

    @Test func theMenuBarHasSettingsQuitAndEditing() throws {
        var opened = 0
        let menu = AppMainMenu.make { opened += 1 }
        #expect(menu.items.map(\.title) == ["Notchy", "Edit", "Window"])
        let app = try #require(menu.items.first?.submenu)
        let settings = try #require(app.items.first { $0.title == "Settings…" })
        #expect(settings.keyEquivalent == ",")
        _ = settings.target?.perform(settings.action)
        #expect(opened == 1)
        #expect(app.items.contains { $0.keyEquivalent == "q" && $0.action == #selector(NSApplication.terminate(_:)) })
        let edit = try #require(menu.items[1].submenu)
        #expect(edit.items.contains { $0.keyEquivalent == "v" && $0.action == #selector(NSText.paste(_:)) })
    }
}
