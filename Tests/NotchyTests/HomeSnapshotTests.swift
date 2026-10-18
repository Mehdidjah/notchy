import AppKit
import SwiftUI
import Testing
@testable import Notchy

/// Renders the open island's header and Home row to PNG files for a visual check. Runs only
/// with `NOTCHY_HOME_SNAPSHOTS` set to an output folder.
@MainActor
struct HomeSnapshotTests {
    /// The seven-tab minimum content width plus the 12-pt open insets.
    private static let islandWidth: CGFloat = 850 + 24
    private static let headerHeight: CGFloat = 32
    /// The shell's content insets (14 + 12 pt a side) and the Home tab's 8-pt padding.
    private static let rowWidth = islandWidth - 52 - 16
    private static let rowHeight = NotchTab.standardOpenHeight - headerHeight - 16

    @Test func rendersTheOpenHomeTab() async throws {
        guard let path = ProcessInfo.processInfo.environment["NOTCHY_HOME_SNAPSHOTS"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "notchy.home-snapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let start = Date()
        let timerSettings = TimerSettings(defaults: defaults)
        timerSettings.notificationsEnabled = false
        timerSettings.soundEnabled = false
        let timer = TimerManager(settings: timerSettings, sound: SilentSound(), notifier: SilentNotifier(), clock: { start })
        timer.start(duration: 25 * 60)
        timer.tick(now: start.addingTimeInterval(334))
        defer { timer.stop() }

        let music = MusicManager(settings: MediaSettings(defaults: defaults))
        music.injectSnapshotForPreview(MediaPlaybackSnapshot(
            source: .spotify, isPlaying: true, title: "Ocean Drive", artist: "Sample Artist", album: "Waves",
            position: 122, duration: 154, isShuffled: false, repeatMode: .off,
            trackIdentifier: "snapshot", artworkData: Self.coverData(), lastUpdated: Date()
        ))
        let deadline = Date().addingTimeInterval(3)
        while music.albumArt === MusicManager.defaultArtwork, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let model = NotchViewModel(activityCenter: IslandActivityCenter(), settings: UserSettings(defaults: defaults))
        model.openPinned()
        let calendar = CalendarStore(settings: CalendarSettings(defaults: defaults))
        let mediaSettings = MediaSettings(defaults: defaults)
        let apps = HomeAppShortcutsStore(defaults: defaults)
        apps.pin(["Calculator", "Calendar", "Notes", "Maps", "Photos", "Preview"]
            .map { URL(fileURLWithPath: "/System/Applications/\($0).app") })
        let weatherSettings = WeatherSettings(defaults: defaults, locale: Locale(identifier: "en_GB"))
        let report = WeatherReport(temperature: 26.8, apparentTemperature: 28.1, code: 2, isDay: false, place: "Lisbon",
                                   query: weatherSettings.query, fetchedAt: Date())
        defaults.set(try JSONEncoder().encode(report), forKey: "weather.lastReport")
        let weather = WeatherStore(settings: weatherSettings, locator: SnapshotLocator(), defaults: defaults)

        let slots = HomeCardLayout.plan(Set(HomeCardKind.allCases).subtracting([.lyrics, .mirror]),
                                        width: Self.rowWidth, height: Self.rowHeight, timerRunning: true)
        let row = HStack(spacing: HomeCardLayout.spacing) {
            ForEach(slots, id: \.kind) { slot in
                Group {
                    switch slot.kind {
                    case .timer: HomeTimerCard(manager: timer, settings: timerSettings)
                    case .media: MediaCardView(manager: music, settings: mediaSettings, showsInlineLyrics: false)
                    case .apps: HomeAppsGrid(height: Self.rowHeight, store: apps)
                    case .calendar: HomeCalendarCard(model: model, store: calendar, settings: calendar.settings)
                    case .weather: HomeWeatherCard(model: model, store: weather)
                    case .lyrics, .mirror: EmptyView()
                    }
                }
                .frame(width: slot.width, height: Self.rowHeight)
            }
        }
        .frame(width: Self.rowWidth, height: Self.rowHeight, alignment: .leading)

        let island = VStack(spacing: 0) {
            NotchHeaderView(model: model)
                .frame(height: Self.headerHeight)
            row.padding(8)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .frame(width: Self.islandWidth, height: NotchTab.standardOpenHeight + 12)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32).fill(.black))
        .padding(16)
        .background(Color(white: 0.85))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: island)
        renderer.scale = 2
        let rendered = try #require(renderer.cgImage)
        let image = try #require(Self.standardRGB(rendered))
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("home.png"))
    }

    /// App icons can make the renderer produce extended-range pixels; viewers read the PNG
    /// correctly only once it is matched to 8-bit sRGB.
    private static func standardRGB(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// A stand-in cover: a deep blue gradient crossed by lighter bands.
    private static func coverData() -> Data? {
        let size = NSSize(width: 600, height: 600)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.05, green: 0.12, blue: 0.25, alpha: 1),
                                NSColor(red: 0.16, green: 0.35, blue: 0.55, alpha: 1)])?
                .draw(in: rect, angle: 70)
            NSColor.white.withAlphaComponent(0.12).setFill()
            for band in 0..<9 {
                let y = CGFloat(band) * 70 + 10
                NSBezierPath(ovalIn: NSRect(x: -80, y: y, width: 760, height: 26)).fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private final class SilentSound: TimerSoundPlaying {
    func play(named name: String, looping: Bool) {}
    func stop() {}
}

private final class SilentNotifier: TimerCompletionNotifying {
    func prepare() {}
    func notifyCompletion(name: String, duration: TimeInterval) {}
}

@MainActor
private final class SnapshotLocator: WeatherLocating {
    let access = WeatherLocationAccess.granted
    var onAccessChange: (() -> Void)?

    func requestAccess() {}

    func locate() async throws -> WeatherPlace {
        throw WeatherLocationError.unavailable
    }
}
