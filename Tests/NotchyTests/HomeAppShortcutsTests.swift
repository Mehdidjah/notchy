import Foundation
import Testing
@testable import Notchy

@MainActor
struct HomeAppShortcutsTests {
    private static let systemApps = ["Calculator", "Calendar", "Notes", "Maps", "Photos", "Preview", "TextEdit"]
        .map { URL(fileURLWithPath: "/System/Applications/\($0).app") }
        .filter { FileManager.default.fileExists(atPath: $0.path) }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "notchy.home-apps.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func promotingMovesAnAppToTheFrontOnce() {
        #expect(HomeAppRecents.promoting("/b", in: ["/a", "/b", "/c"]) == ["/b", "/a", "/c"])
        #expect(HomeAppRecents.promoting("/d", in: ["/a", "/b", "/c"], limit: 3) == ["/d", "/a", "/b"])
        #expect(HomeAppRecents.promoting("/a", in: []) == ["/a"])
    }

    @Test func activationsBuildTheRecentListAndSkipFinderAndBackgroundApps() throws {
        try #require(Self.systemApps.count >= 3)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAppShortcutsStore(defaults: defaults)
        let first = Self.systemApps[0], second = Self.systemApps[1], third = Self.systemApps[2]

        store.noteActivation(of: first, bundleIdentifier: "one", isRegular: true)
        store.noteActivation(of: second, bundleIdentifier: "two", isRegular: true)
        store.noteActivation(of: third, bundleIdentifier: "three", isRegular: false)
        store.noteActivation(of: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                             bundleIdentifier: "com.apple.finder", isRegular: true)
        store.noteActivation(of: URL(fileURLWithPath: "/tmp/helper"), bundleIdentifier: "helper", isRegular: true)
        store.noteActivation(of: first, bundleIdentifier: "one", isRegular: true)

        #expect(store.recent.map(\.url) == [first, second])
        #expect(store.shortcuts.map(\.url) == [first, second])
        #expect(HomeAppShortcutsStore(defaults: defaults).recent.map(\.url) == [first, second])
    }

    @Test func pinnedAppsReplaceTheRecentOnesAndStopAtSix() throws {
        try #require(Self.systemApps.count >= 2)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAppShortcutsStore(defaults: defaults)
        store.noteActivation(of: Self.systemApps[0], bundleIdentifier: "one", isRegular: true)

        let missing = URL(fileURLWithPath: "/Applications/Notchy Missing Test App.app")
        store.pin([Self.systemApps[1], Self.systemApps[1], URL(fileURLWithPath: "/tmp/file.txt"), missing])
        #expect(store.pinned.map(\.url) == [Self.systemApps[1], missing])
        #expect(store.shortcuts.map(\.url) == [Self.systemApps[1], missing])
        // Deleted apps drop out when the list is read back.
        #expect(HomeAppShortcutsStore(defaults: defaults).pinned.map(\.url) == [Self.systemApps[1]])

        store.pin((0..<10).map { URL(fileURLWithPath: "/Applications/Test \($0).app") })
        #expect(store.pinned.count == HomeAppShortcutsStore.capacity)
        #expect(!store.canPinMore)

        store.movePinned(fromOffsets: [0], toOffset: 2)
        #expect(store.pinned[1].url == Self.systemApps[1])
        store.unpin(store.pinned[1])
        #expect(!store.pinned.map(\.url).contains(Self.systemApps[1]))
    }

    @Test func shortcutNamesDropTheAppExtension() throws {
        let calculator = try #require(Self.systemApps.first)
        #expect(!HomeAppShortcut(url: calculator).name.hasSuffix(".app"))
    }

    @Test func theGridIsTwoTilesWideAndGoesFirstWhenTheRowIsFull() {
        #expect(HomeAppGridMetrics.tileSide(forHeight: 148) == 45)
        #expect(HomeAppGridMetrics.width(forHeight: 148) == 96)
        #expect(HomeCardLayout.widthRange(for: .apps, height: 148) == .fixed(96))

        let kinds: Set<HomeCardKind> = [.timer, .media, .apps, .calendar]
        let roomy = HomeCardLayout.plan(kinds, width: 782, height: 148)
        #expect(roomy.map(\.kind) == [.timer, .media, .apps, .calendar])
        let tight = HomeCardLayout.plan(kinds, width: 590, height: 148, timerRunning: true)
        #expect(tight.map(\.kind) == [.timer, .media, .calendar])
    }
}
