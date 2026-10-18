import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// An app on the Home grid.
struct HomeAppShortcut: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String

    var id: String { url.path }

    init(url: URL) {
        self.url = url
        let displayName = FileManager.default.displayName(atPath: url.path)
        name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }
}

/// Most-recently-used ordering of app paths.
enum HomeAppRecents {
    static let limit = 12

    /// `path` moved to the front, without duplicates, at most `limit` entries long.
    static func promoting(_ path: String, in paths: [String], limit: Int = limit) -> [String] {
        Array(([path] + paths.filter { $0 != path }).prefix(limit))
    }
}

/// The apps the Home grid offers: the pinned ones, or while nothing is pinned the apps used
/// most recently, learnt from app activations. Finder and Notchy itself are never counted.
/// Both lists persist as bundle paths; apps that have been deleted drop out on load.
@MainActor
final class HomeAppShortcutsStore: ObservableObject {
    static let shared = HomeAppShortcutsStore()
    static let capacity = 6

    private enum Key {
        static let pinned = "home.apps.pinned"
        static let recent = "home.apps.recent"
    }

    private static let excludedBundleIdentifiers: Set<String> = ["com.apple.finder"]

    @Published private(set) var pinned: [HomeAppShortcut]
    @Published private(set) var recent: [HomeAppShortcut]

    var shortcuts: [HomeAppShortcut] {
        Array((pinned.isEmpty ? recent : pinned).prefix(Self.capacity))
    }

    var canPinMore: Bool { pinned.count < Self.capacity }

    private let defaults: UserDefaults
    private let ownBundleURL = Bundle.main.bundleURL.standardizedFileURL
    private var activationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinned = Self.load(defaults.stringArray(forKey: Key.pinned))
        recent = Self.load(defaults.stringArray(forKey: Key.recent))
    }

    func start() {
        guard activationObserver == nil else { return }
        if recent.isEmpty { seedFromRunningApps() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let url = app?.bundleURL
            let bundleIdentifier = app?.bundleIdentifier
            let isRegular = app?.activationPolicy == .regular
            MainActor.assumeIsolated {
                self?.noteActivation(of: url, bundleIdentifier: bundleIdentifier, isRegular: isRegular)
            }
        }
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func noteActivation(of url: URL?, bundleIdentifier: String?, isRegular: Bool) {
        guard let url, isRegular, url.pathExtension == "app",
              url.standardizedFileURL != ownBundleURL,
              !Self.excludedBundleIdentifiers.contains(bundleIdentifier ?? "") else { return }
        let current = recent.map(\.url.path)
        let paths = HomeAppRecents.promoting(url.path, in: current)
        guard paths != current else { return }
        recent = paths.map { path in recent.first { $0.url.path == path } ?? HomeAppShortcut(url: URL(fileURLWithPath: path)) }
        defaults.set(paths, forKey: Key.recent)
    }

    func pin(_ urls: [URL]) {
        var paths = pinned.map(\.url.path)
        for url in urls where url.pathExtension == "app" && !paths.contains(url.path) && paths.count < Self.capacity {
            paths.append(url.path)
        }
        setPinned(paths)
    }

    func unpin(_ shortcut: HomeAppShortcut) {
        setPinned(pinned.map(\.url.path).filter { $0 != shortcut.url.path })
    }

    func movePinned(fromOffsets source: IndexSet, toOffset destination: Int) {
        var paths = pinned.map(\.url.path)
        paths.move(fromOffsets: source, toOffset: destination)
        setPinned(paths)
    }

    func open(_ shortcut: HomeAppShortcut) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: shortcut.url, configuration: configuration, completionHandler: nil)
    }

    private func setPinned(_ paths: [String]) {
        pinned = paths.map { HomeAppShortcut(url: URL(fileURLWithPath: $0)) }
        defaults.set(paths, forKey: Key.pinned)
    }

    /// Running apps in launch order, then the frontmost one, so it leads.
    private func seedFromRunningApps() {
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications + [workspace.frontmostApplication].compactMap({ $0 }) {
            noteActivation(of: app.bundleURL, bundleIdentifier: app.bundleIdentifier, isRegular: app.activationPolicy == .regular)
        }
    }

    private static func load(_ paths: [String]?) -> [HomeAppShortcut] {
        (paths ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { HomeAppShortcut(url: URL(fileURLWithPath: $0)) }
    }
}

/// Icons read once per app bundle.
@MainActor
enum HomeAppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forPath path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

/// Sizes of the app grid: two columns by three rows of square tiles, 6 pt apart, as tall as
/// the Home row.
enum HomeAppGridMetrics {
    static let columns = 2
    static let rows = 3
    static let spacing: CGFloat = 6

    static func tileSide(forHeight height: CGFloat) -> CGFloat {
        max(0, ((height - spacing * CGFloat(rows - 1)) / CGFloat(rows)).rounded(.down))
    }

    static func width(forHeight height: CGFloat) -> CGFloat {
        tileSide(forHeight: height) * CGFloat(columns) + spacing * CGFloat(columns - 1)
    }
}

/// Home's app grid: each app icon on a faint rounded tile; a click opens or switches to it.
struct HomeAppsGrid: View {
    let height: CGFloat
    @ObservedObject private var store: HomeAppShortcutsStore

    init(height: CGFloat, store: HomeAppShortcutsStore = .shared) {
        self.height = height
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        let side = HomeAppGridMetrics.tileSide(forHeight: height)
        let shortcuts = store.shortcuts
        VStack(spacing: HomeAppGridMetrics.spacing) {
            ForEach(0..<HomeAppGridMetrics.rows, id: \.self) { row in
                HStack(spacing: HomeAppGridMetrics.spacing) {
                    ForEach(0..<HomeAppGridMetrics.columns, id: \.self) { column in
                        let index = row * HomeAppGridMetrics.columns + column
                        if shortcuts.indices.contains(index) {
                            let shortcut = shortcuts[index]
                            HomeAppTile(shortcut: shortcut, side: side) { store.open(shortcut) }
                        } else {
                            HomeAppTileBackground(side: side, isHovering: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeAppTile: View {
    let shortcut: HomeAppShortcut
    let side: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HomeAppTileBackground(side: side, isHovering: isHovering)
                .overlay {
                    Image(nsImage: HomeAppIconCache.icon(forPath: shortcut.url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side * 0.78, height: side * 0.78)
                        .scaleEffect(isHovering ? 1.06 : 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) { isHovering = hovering }
        }
        .help(shortcut.name)
        .accessibilityLabel("Open \(shortcut.name)")
    }
}

private struct HomeAppTileBackground: View {
    let side: CGFloat
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.27, style: .continuous)
            .fill(Color.white.opacity(isHovering ? 0.13 : 0.06))
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
    }
}

/// Settings rows for the app grid: the pinned apps, with buttons to add, remove and reorder.
struct HomeAppShortcutsSettingsRows: View {
    @ObservedObject var store: HomeAppShortcutsStore
    @State private var isImporterPresented = false

    var body: some View {
        if store.pinned.isEmpty {
            Text("Showing the apps you used most recently. Pin apps to keep the same six.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(store.pinned) { shortcut in
            HStack(spacing: 8) {
                Image(nsImage: HomeAppIconCache.icon(forPath: shortcut.url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(shortcut.name)
                Spacer()
                Button {
                    store.unpin(shortcut)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Unpin \(shortcut.name)")
            }
        }
        .onMove { store.movePinned(fromOffsets: $0, toOffset: $1) }
        Button("Pin Apps…") { isImporterPresented = true }
            .disabled(!store.canPinMore)
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.application],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { store.pin(urls) }
            }
    }
}
