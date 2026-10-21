import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import Notchy

/// The website's closed-notch shots: the island shut over the camera housing, once bare and
/// once for each live activity the app registers, each on made-up data with its own settings
/// suite. Nothing here reads the user's music, calendar, Claude sessions, shelf, clipboard,
/// camera or settings.
@MainActor
@Suite(.serialized)
struct WebsiteShotsClosedTests {
    // MARK: - The bare notch

    @Test func idle() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        island.settings.hapticsEnabled = false
        try await island.renderClosed(to: output.appendingPathComponent("closed-idle.png"))
    }

    // MARK: - Music

    @Test func music() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let mediaSettings = MediaSettings(defaults: try WebsiteShots.defaults())
        mediaSettings.enableSneakPeek = false
        mediaSettings.enableLyrics = false
        let music = MusicManager(settings: mediaSettings)
        music.injectSnapshotForPreview(MediaPlaybackSnapshot(
            source: .spotify, isPlaying: true, title: "Golden Hour", artist: "Sunset Tapes", album: "Coastline",
            position: 74, duration: 212, isShuffled: false, repeatMode: .off,
            trackIdentifier: "spotify:track:golden-hour", artworkData: ClosedShotArt.goldenHourCover(),
            lastUpdated: Date()
        ))
        // The cover is analysed off the main actor; wait for it to land.
        let deadline = Date().addingTimeInterval(3)
        while music.albumArt === MusicManager.defaultArtwork, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        island.center.register(MusicLiveActivity(manager: music, settings: mediaSettings))
        try await Task.sleep(for: .milliseconds(50))
        island.center.reevaluate()
        try await island.renderClosed(to: output.appendingPathComponent("closed-music.png"), settle: .milliseconds(1_100))
    }

    // MARK: - Timer

    @Test func timer() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let timerSettings = TimerSettings(defaults: try WebsiteShots.defaults())
        timerSettings.notificationsEnabled = false
        timerSettings.soundEnabled = false
        let clock = ClosedShotClock()
        let timer = TimerManager(settings: timerSettings, sound: ClosedShotSilentSound(), notifier: ClosedShotSilentNotifier(), clock: { clock.now })
        defer { timer.stop() }
        let focus = try #require(timerSettings.presets.first { $0.name == "Focus" })
        timer.start(preset: focus)
        // Ten minutes and 18 seconds into a 25-minute focus session: 14:42 left.
        clock.advance(by: 10 * 60 + 18)
        timer.tick()
        island.center.register(TimerClosedActivity(manager: timer, settings: timerSettings))
        // `ImageRenderer` cannot draw the closed island's drop target (an AppKit view); the
        // Shelf tab off removes it and changes nothing else on the closed notch.
        island.settings.showShelfTab = false
        // The timer glyph is tinted by a layer filter that the offscreen window capture leaves
        // out (it comes out white), so this shot is drawn by SwiftUI's own renderer instead.
        try ClosedShotRenderer.writeClosed(island, to: output.appendingPathComponent("closed-timer.png"))
    }

    // MARK: - Claude Code

    @Test func claude() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let claudeSettings = ClaudeSettings(defaults: try WebsiteShots.defaults())
        let usage = ClaudeUsageStore()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, loadPlan: { nil }, usage: usage)
        monitor.apply([ClaudeLiveSession(
            pid: 4_812, sessionID: "a3f1c9", cwd: "/Users/sam/Projects/harbor-app", status: .busy, name: nil, updatedAt: Date(),
            context: ClaudeContextUsage(tokens: 184_000, window: 1_000_000, model: "claude-opus-5-5")
        )])
        let attention = ClaudeAttention(monitor: monitor, usage: usage, settings: claudeSettings)
        attention.recompute()
        island.center.register(ClaudeClosedActivity(monitor: monitor, settings: claudeSettings, attention: attention))
        try await island.renderClosed(to: output.appendingPathComponent("closed-claude.png"))
    }

    // MARK: - Calendar reminder

    @Test func reminder() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let fixedNow = ClosedShotTime.today(hour: 10, minute: 26)
        let calendarSettings = CalendarSettings(defaults: try WebsiteShots.defaults())
        // The countdown in minutes and seconds says "a meeting is about to start" on its own,
        // where the default ring needs the open island to explain it.
        calendarSettings.reminderPresentationStyle = .digital
        let reminder = ReminderLiveActivityModel(
            settings: calendarSettings,
            events: Empty().eraseToAnyPublisher(),
            clock: { fixedNow },
            sneakPeek: { _ in },
            usesTimers: false
        )
        let work = CalendarSource(
            accountName: "iCloud", id: "website-work", title: "Work",
            color: CalendarColor(red: 0.62, green: 0.36, blue: 0.96),
            isSubscribed: false, isReminderList: false
        )
        let start = fixedNow.addingTimeInterval(4 * 60)
        reminder.apply(events: [CalendarEntry(
            itemIdentifier: "design-review", start: start, end: start.addingTimeInterval(30 * 60),
            title: "Design review", location: "Studio 2", kind: .event(.accepted), calendar: work
        )])
        #expect(reminder.isActivityVisible)
        island.center.register(reminder)
        try await island.renderClosed(to: output.appendingPathComponent("closed-reminder.png"))
    }

    // MARK: - Volume and brightness

    @Test func volume() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let presenter = SystemHUDPresenter(settings: SystemHUDSettings(defaults: try WebsiteShots.defaults()), activityCenter: island.center)
        island.center.register(InlineHUDActivity(presenter: presenter))
        presenter.presentVolume(level: 0.62, isBluetooth: false)
        island.center.reevaluate()
        try await island.renderClosed(to: output.appendingPathComponent("closed-volume.png"), settle: .milliseconds(300))
    }

    @Test func brightness() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let presenter = SystemHUDPresenter(settings: SystemHUDSettings(defaults: try WebsiteShots.defaults()), activityCenter: island.center)
        island.center.register(InlineHUDActivity(presenter: presenter))
        presenter.presentBrightness(level: 0.7)
        island.center.reevaluate()
        try await island.renderClosed(to: output.appendingPathComponent("closed-brightness.png"), settle: .milliseconds(300))
    }

    // MARK: - Shelf

    @Test func shelf() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let folder = try WebsiteShots.temporaryDirectory("closed-shelf")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ShelfStore(
            persistence: nil,
            temporaryFiles: ShelfTemporaryFileStore(rootDirectory: folder.appendingPathComponent("Drops", isDirectory: true))
        )
        let brief = folder.appendingPathComponent("Harbor brief.pdf")
        try Data("Harbor brief".utf8).write(to: brief)
        store.add([
            try ShelfItem.file(at: brief),
            ShelfItem.text("Pick up the prints from the studio at 4"),
            ShelfItem.link(try #require(URL(string: "https://example.com/lisbon-guide"))),
        ])
        #expect(store.count == 3)
        island.center.register(ShelfLiveActivity(store: store, settings: island.settings))
        try await island.renderClosed(to: output.appendingPathComponent("closed-shelf.png"))
    }

    // MARK: - Caps Lock

    @Test func capsLock() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let hudSettings = SystemHUDSettings(defaults: try WebsiteShots.defaults())
        let presenter = SystemHUDPresenter(settings: hudSettings, activityCenter: island.center)
        hudSettings.showCapsLockLabel = true
        let monitor = CapsLockMonitor(readState: { true })
        island.center.register(CapsLockActivity(monitor: monitor, settings: hudSettings, presenter: presenter))
        monitor.poll()
        island.center.reevaluate()
        try await island.renderClosed(to: output.appendingPathComponent("closed-capslock.png"))
    }

    // MARK: - Face Check

    @Test func faceCheck() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let activity = FaceCheckLiveActivity(haptics: ClosedShotSilentHaptics())
        island.center.register(activity)
        activity.begin(reason: "Reveal a hidden item")
        island.center.reevaluate()
        let layout = try #require(island.model.closedActivityLayout())
        // The unfolded check is much taller than the closed notch: room for it and its shadow.
        let canvas = CGSize(width: max(layout.contentWidth, 252) + 28 + 80, height: max(layout.outerHeight, 200) + 40)
        try await WebsiteShots.write(
            NotchRootView(model: island.model).frame(width: canvas.width, height: canvas.height),
            size: canvas,
            scale: 4,
            to: output.appendingPathComponent("closed-facecheck.png"),
            settle: .milliseconds(400),
            beforeCapture: {
                activity.finish(recognized: true, message: "It's you.")
                island.center.reevaluate()
                // The check draws itself in about 1.2 s; the result holds for 1.7 s.
                try await Task.sleep(for: .milliseconds(1_300))
            }
        )
    }

    // MARK: - Copy peek

    @Test func copiedPeek() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        island.settings.hapticsEnabled = false
        let clip = Clip(
            title: "Meet at the studio, 3rd floor", value: "Meet at the studio, 3rd floor", detail: "Messages",
            kind: .text, style: .dark, symbolName: ""
        )
        island.model.acceptCapturedClip(clip)
        island.model.presentCapturePeek(for: clip)
        #expect(island.model.state == .peeking)
        let width = max(WebsiteShots.geometry.syntheticOrHardwareWidth - NotchSilhouette.idleContentInset + 28, NotchSilhouette.sneakPeekMinimumWidth)
        let canvas = CGSize(width: width + 80, height: WebsiteShots.geometry.topInset + NotchSilhouette.sneakPeekRowHeight + 40)
        try await WebsiteShots.write(
            NotchRootView(model: island.model).frame(width: canvas.width, height: canvas.height),
            size: canvas,
            scale: 4,
            to: output.appendingPathComponent("peek-copied.png"),
            settle: .milliseconds(500)
        )
    }
}

// MARK: - Rendering

/// Draws the closed island with `ImageRenderer`, for activities whose look depends on
/// something the window capture in `WebsiteShots.write` cannot reproduce. Same canvas, scale
/// and trimming as `WebsiteIsland.renderClosed`. It draws a single frame, so it suits only
/// views that need no `onAppear`, task or timeline to reach their look.
@MainActor
private enum ClosedShotRenderer {
    static func writeClosed(_ island: WebsiteIsland, to url: URL, scale: CGFloat = 4) throws {
        island.center.reevaluate()
        let width = island.model.closedActivityLayout().map { $0.contentWidth + 28 } ?? WebsiteShots.geometry.syntheticOrHardwareWidth
        let canvas = CGSize(width: width + 80, height: WebsiteShots.geometry.topInset + 48)
        let renderer = ImageRenderer(content: NotchRootView(model: island.model)
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = scale
        renderer.isOpaque = false
        let rendered = try #require(renderer.cgImage)
        let image = try #require(standardRGB(rendered))
        let shot = try #require(trimmed(image))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// 8-bit sRGB with premultiplied alpha, which the PNG writer and the trimming expect.
    private static func standardRGB(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Cut down to what is drawn plus six pixels, as `WebsiteShots.write` does.
    private static func trimmed(_ image: CGImage, padding: Int = 6) -> CGImage? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return image }
        let width = image.width, height = image.height, rowBytes = image.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where bytes[y * rowBytes + x * 4 + 3] > 2 {
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

// MARK: - Sample art and time

@MainActor
private enum ClosedShotArt {
    /// An original cover for "Golden Hour": a low sun over the sea at dusk, drawn from shapes.
    static func goldenHourCover() -> Data? {
        let size = NSSize(width: 600, height: 600)
        let image = NSImage(size: size, flipped: false) { rect in
            // Sky: dusk purple at the top to amber at the horizon.
            NSGradient(colors: [
                NSColor(red: 0.98, green: 0.62, blue: 0.29, alpha: 1),
                NSColor(red: 0.93, green: 0.38, blue: 0.36, alpha: 1),
                NSColor(red: 0.42, green: 0.20, blue: 0.47, alpha: 1),
            ])?.draw(in: rect, angle: 90)
            // The sun, half set.
            let horizon: CGFloat = 230
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: horizon, width: rect.width, height: rect.height - horizon)).addClip()
            NSGradient(colors: [
                NSColor(red: 1.0, green: 0.90, blue: 0.62, alpha: 1),
                NSColor(red: 1.0, green: 0.70, blue: 0.36, alpha: 1),
            ])?.draw(in: NSBezierPath(ovalIn: NSRect(x: 180, y: horizon - 120, width: 240, height: 240)), angle: 90)
            NSGraphicsContext.restoreGraphicsState()
            // The sea, with the sun's reflection broken into bands.
            NSGradient(colors: [
                NSColor(red: 0.16, green: 0.12, blue: 0.30, alpha: 1),
                NSColor(red: 0.36, green: 0.20, blue: 0.40, alpha: 1),
            ])?.draw(in: NSRect(x: 0, y: 0, width: rect.width, height: horizon), angle: 90)
            NSColor(red: 1.0, green: 0.78, blue: 0.48, alpha: 0.75).setFill()
            for band in 0 ..< 7 {
                let width = 210 - CGFloat(band) * 24
                let y = horizon - 22 - CGFloat(band) * 30
                NSBezierPath(roundedRect: NSRect(x: (rect.width - width) / 2, y: y, width: width, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private enum ClosedShotTime {
    /// Today at a fixed time of day, so countdowns and clock faces read naturally.
    static func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Fakes

/// A clock the shot moves by hand.
private final class ClosedShotClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = ClosedShotTime.today(hour: 9, minute: 30)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class ClosedShotSilentSound: TimerSoundPlaying {
    func play(named name: String, looping: Bool) {}
    func stop() {}
}

private final class ClosedShotSilentNotifier: TimerCompletionNotifying {
    func prepare() {}
    func notifyCompletion(name: String, duration: TimeInterval) {}
}

private final class ClosedShotSilentHaptics: HapticFeedbackPerforming {
    func perform() {}
}
