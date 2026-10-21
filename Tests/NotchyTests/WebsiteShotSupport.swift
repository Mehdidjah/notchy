import AppKit
import SwiftUI
import Testing
@testable import Notchy

/// Shared pieces of the website screenshots (the `WebsiteShots…Tests` suites): where they are
/// written, the Mac they are drawn for, an island with its own settings, and the renderer.
///
/// The suites run only when NOTCHY_WEBSITE_SHOTS names the folder to write to:
///
///   NOTCHY_WEBSITE_SHOTS="$PWD/website/public/assets/app" swift test --filter WebsiteShots
///
/// Every shot is built on made-up sample data in temporary folders and its own defaults
/// suites; none of them reads the user's clipboard, files, notes, music, calendar, Claude
/// sessions, camera or settings.
@MainActor
enum WebsiteShots {
    static let output = ProcessInfo.processInfo.environment["NOTCHY_WEBSITE_SHOTS"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// A 14-inch MacBook Pro's notch.
    static let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        topInset: 32,
        hardwareNotchWidth: 185,
        isHardwareNotch: true
    )

    /// A fresh folder for a shot's sample files, removed when the test process ends.
    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchy-website-shots-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A defaults suite of its own, so sample settings never reach the user's.
    static func defaults() throws -> UserDefaults {
        let suite = "notchy.website-shots.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Draws `view` at `size` points and `scale` pixels per point onto a clear background and
    /// writes it as a PNG. `beforeCapture` runs after the view has settled, right before the
    /// pixels are taken, for state that must be set once the view is on screen.
    static func write(
        _ view: some View,
        size: CGSize,
        scale: CGFloat = 2,
        to url: URL,
        settle: Duration = .milliseconds(900),
        beforeCapture: @MainActor () async throws -> Void = {}
    ) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: settle)
        try await beforeCapture()
        try await Task.sleep(for: .milliseconds(120))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = try #require(trimmed(rep))
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// The image cut down to what is drawn, the soft edge of the shadow included, plus a few
    /// pixels, so the website can place a shot by its visible edges.
    private static func trimmed(_ rep: NSBitmapImageRep, padding: Int = 6) -> CGImage? {
        guard let image = rep.cgImage, let data = rep.bitmapData else { return rep.cgImage }
        let width = rep.pixelsWide, height = rep.pixelsHigh, rowBytes = rep.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where data[y * rowBytes + x * 4 + 3] > 2 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let rect = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width, maxX + padding + 1) - max(0, minX - padding),
            height: min(height, maxY + padding + 1) - max(0, minY - padding)
        )
        return image.cropping(to: rect)
    }
}

/// The real island (`NotchRootView`) with its own settings and activity center.
@MainActor
final class WebsiteIsland {
    let model: NotchViewModel
    let center: IslandActivityCenter
    let settings: UserSettings

    init(items: [Clip] = []) throws {
        center = IslandActivityCenter()
        settings = UserSettings(defaults: try WebsiteShots.defaults())
        settings.openOnHover = false
        model = NotchViewModel(items: items, activityCenter: center, settings: settings)
        model.updateNotchGeometry(WebsiteShots.geometry)
    }

    func open(_ tab: NotchTab) {
        model.openPinned()
        model.selectTab(tab)
    }

    /// The open island at its open size, with room around it for the shadow. `content`
    /// supplies the selected tab's view built on sample data; without it the tab is built as
    /// the app builds it, which is only safe for tabs that read nothing of the user's.
    func renderOpen(
        to url: URL,
        scale: CGFloat = 2,
        content: (@MainActor @Sendable (NotchTab) -> AnyView?)? = nil,
        settle: Duration = .milliseconds(900),
        beforeCapture: @MainActor () async throws -> Void = {}
    ) async throws {
        let size = NotchGeometryResolver.metrics(
            state: .pinnedOpen,
            geometry: WebsiteShots.geometry,
            preferredExpandedWidth: settings.openNotchWidth,
            tab: model.selectedTab,
            tabCount: model.availableTabs.count,
            extraOpenHeight: model.extraOpenHeight
        ).renderedSize
        let canvas = CGSize(width: size.width + 120, height: size.height + 70)
        try await WebsiteShots.write(
            NotchRootView(model: model)
                .environment(\.notchTabContentOverride, content)
                .frame(width: canvas.width, height: canvas.height),
            size: canvas,
            scale: scale,
            to: url,
            settle: settle,
            beforeCapture: beforeCapture
        )
    }

    /// The closed island showing whatever live activity its center ranks first, with room
    /// around it for the hover shadow.
    func renderClosed(
        to url: URL,
        scale: CGFloat = 4,
        hovering: Bool = false,
        settle: Duration = .milliseconds(700),
        beforeCapture: @MainActor () async throws -> Void = {}
    ) async throws {
        center.reevaluate()
        if hovering { model.setHovered(true) }
        let width = model.closedActivityLayout().map { $0.contentWidth + 28 } ?? WebsiteShots.geometry.syntheticOrHardwareWidth
        let canvas = CGSize(width: width + 80, height: WebsiteShots.geometry.topInset + 48)
        try await WebsiteShots.write(
            NotchRootView(model: model).frame(width: canvas.width, height: canvas.height),
            size: canvas,
            scale: scale,
            to: url,
            settle: settle,
            beforeCapture: beforeCapture
        )
    }
}
