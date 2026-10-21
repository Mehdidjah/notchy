import AppKit
import Foundation
import Testing
@testable import Notchy

/// The website's Home tab, every card on: a song playing, the weather in Lisbon, the day's
/// next event, six pinned apps and a focus timer part way through.
///
/// Home reads the app's shared stores, so each one is filled before the island is drawn and
/// put back afterwards: the player is fed a reading (no player is asked; it only looks the
/// made-up song up in the public catalogue for its explicit flag), the calendar shows
/// injected events (EventKit is never read), the weather store starts from a saved report
/// (no location, no forecast fetch) and the app grid is pinned to system apps. The keys
/// this writes to the test runner's own defaults are restored.
@MainActor
@Suite(.serialized)
struct WebsiteShotsHomeTests {
    @Test func homeTab() async throws {
        guard let output = WebsiteShots.output else { return }

        let savedDefaults = HomeShotDefaults(keys: HomeShotData.touchedDefaultsKeys)
        let layout = HomeLayoutState.shared
        let savedLayout = (layout.showsMediaPlayer, layout.showsCalendar, layout.showsMirror)
        defer {
            TimerManager.shared.stop()
            for shortcut in HomeAppShortcutsStore.shared.pinned { HomeAppShortcutsStore.shared.unpin(shortcut) }
            CalendarStore.shared.injectForPreview(entries: [], calendars: [])
            (layout.showsMediaPlayer, layout.showsCalendar, layout.showsMirror) = savedLayout
            savedDefaults.restore()
        }

        // Weather first: the store reads its saved report once, when it is created, and a
        // fresh report for the current settings means opening the island fetches nothing.
        let weatherSettings = WeatherSettings.shared
        let report = HomeShotData.weatherReport(for: weatherSettings.query)
        UserDefaults.standard.set(try JSONEncoder().encode(report), forKey: HomeShotData.weatherReportKey)
        try #require(
            WeatherStore.shared.currentReport != nil,
            "the weather store was created before the report was saved; it would look the weather up"
        )

        // The calendar shows two events today and never touches EventKit.
        CalendarStore.shared.injectForPreview(entries: HomeShotData.events(), calendars: HomeShotData.calendars)

        // Six system apps on the grid.
        let apps = HomeAppShortcutsStore.shared
        for shortcut in apps.pinned { apps.unpin(shortcut) }
        apps.pin(HomeShotData.appURLs)
        try #require(apps.shortcuts.count == HomeShotData.appURLs.count)

        // The card set the app shows for this session.
        let widgets = HomeWidgetSettings.shared
        if widgets.timerCard != .always { widgets.timerCard = .always }
        if !widgets.showsApps { widgets.showsApps = true }
        if !widgets.showsWeather { widgets.showsWeather = true }
        if MediaSettings.shared.enableLyrics { MediaSettings.shared.enableLyrics = false }
        layout.showsMediaPlayer = true
        layout.showsCalendar = true
        layout.showsMirror = false

        // A song, as a player would report it, with its cover analysed.
        let music = MusicManager.shared
        music.injectSnapshotForPreview(try HomeShotData.nowPlaying())
        try await waitUntil("the album cover is analysed") {
            music.albumArt !== MusicManager.defaultArtwork && !music.usingAppIconForArtwork
        }

        // A focus session, started now and shown part way through just before capture.
        let timer = TimerManager.shared
        if let focus = TimerSettings.shared.presets.first(where: { $0.name == "Focus" }) {
            timer.start(preset: focus)
        } else {
            timer.start(duration: 25 * 60, name: "Focus")
        }

        let island = try WebsiteIsland()
        island.open(.home)
        try await island.renderOpen(to: output.appendingPathComponent("tab-home.png"), beforeCapture: {
            try await Self.showTimer(timer, elapsed: HomeShotData.timerElapsed)
        })
    }

    /// Moves the running timer's display `elapsed` into the run. Waits for one of the
    /// timer's own ticks first, so the next is a second away, well after the capture.
    private static func showTimer(_ timer: TimerManager, elapsed: TimeInterval) async throws {
        let tick = timer.remainingTime
        let deadline = Date().addingTimeInterval(2)
        while timer.remainingTime == tick, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        timer.tick(now: (timer.startedAt ?? Date()).addingTimeInterval(elapsed))
    }

    private func waitUntil(
        _ what: String,
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting until \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// The made-up things the Home tab shows.
@MainActor
private enum HomeShotData {
    static let weatherReportKey = "weather.lastReport"

    /// Keys of the test runner's own defaults that filling Home's shared stores can write.
    static let touchedDefaultsKeys = [
        weatherReportKey,
        "home.apps.pinned",
        "home.timerCard",
        "home.showsApps",
        "home.showsWeather",
        "media.enableLyrics",
    ]

    static let appURLs = ["Calculator", "Calendar", "Notes", "Maps", "Photos", "Preview"].map {
        URL(fileURLWithPath: "/System/Applications/\($0).app", isDirectory: true)
    }

    /// 7 min 18 s into a run.
    static let timerElapsed: TimeInterval = 7 * 60 + 18

    // MARK: Weather

    /// Mild and partly cloudy in Lisbon, just fetched, in the unit the settings ask for.
    static func weatherReport(for query: WeatherQuery) -> WeatherReport {
        WeatherReport(
            temperature: query.fahrenheit ? 64 : 18,
            apparentTemperature: query.fahrenheit ? 63 : 17,
            code: 2,
            isDay: true,
            place: "Lisbon",
            query: query,
            fetchedAt: Date()
        )
    }

    // MARK: Calendar

    static let work = CalendarSource(
        accountName: "iCloud",
        id: "website-work",
        title: "Work",
        color: CalendarColor(red: 0.25, green: 0.56, blue: 1),
        isSubscribed: false,
        isReminderList: false
    )

    static let personal = CalendarSource(
        accountName: "iCloud",
        id: "website-personal",
        title: "Personal",
        color: CalendarColor(red: 1, green: 0.62, blue: 0.04),
        isSubscribed: false,
        isReminderList: false
    )

    static let calendars = [work, personal]

    /// Two events later today: a kickoff at two and the release at half past four while the
    /// morning is not over, otherwise starting on the next half hour at least 20 minutes
    /// away; too close to midnight, the first is under way. The card names only the next
    /// one, in a narrow footer, so its title is short.
    static func events(now: Date = Date()) -> [CalendarEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func time(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? now
        }
        func entry(_ id: String, _ title: String, _ start: Date, minutes: Double, _ source: CalendarSource) -> CalendarEntry {
            CalendarEntry(
                itemIdentifier: id,
                start: start,
                end: start.addingTimeInterval(minutes * 60),
                title: title,
                kind: .event(.accepted),
                calendar: source
            )
        }

        if now < time(13, 0) {
            return [
                entry("kickoff", "Kickoff", time(14, 0), minutes: 30, work),
                entry("ship-update", "Ship the update", time(16, 30), minutes: 30, work),
            ]
        }
        let halfHour: TimeInterval = 30 * 60
        let soonest = now.addingTimeInterval(20 * 60).timeIntervalSince(today)
        var first = today.addingTimeInterval((soonest / halfHour).rounded(.up) * halfHour)
        if first > time(23, 0) {
            first = today.addingTimeInterval((now.timeIntervalSince(today) / halfHour).rounded(.down) * halfHour)
        }
        let second = min(first.addingTimeInterval(2 * 3600), time(23, 30))
        if calendar.component(.hour, from: first) < 18 {
            return [
                entry("kickoff", "Kickoff", first, minutes: 30, work),
                entry("ship-update", "Ship the update", second, minutes: 30, work),
            ]
        }
        return [
            entry("dinner", "Dinner", first, minutes: 90, personal),
            entry("call", "Call with Sam", second, minutes: 30, work),
        ]
    }

    // MARK: Music

    /// "Golden Hour" by Sunset Tapes, 1:42 into 3:34, reported by the player just now.
    static func nowPlaying() throws -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: .spotify,
            isPlaying: true,
            title: "Golden Hour",
            artist: "Sunset Tapes",
            album: "Low Tide",
            position: 102,
            duration: 214,
            isShuffled: false,
            repeatMode: .off,
            trackIdentifier: "website:golden-hour",
            artworkURL: nil,
            artworkData: try albumCover(),
            lastUpdated: Date()
        )
    }

    /// An abstract sunset over the sea: a warm sky, a low sun and its broken reflection.
    static func albumCover(side: Int = 600) throws -> Data {
        let size = CGFloat(side)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        func gradient(_ stops: [(CGFloat, CGColor)]) throws -> CGGradient {
            try #require(CGGradient(
                colorsSpace: space,
                colors: stops.map(\.1) as CFArray,
                locations: stops.map(\.0)
            ))
        }

        // Core Graphics counts y from the bottom. The player crops the cover to its middle
        // band, so the sun sits just above the middle, right of centre.
        let horizon = size * 0.53
        let sky = try gradient([
            (0, color(0.98, 0.62, 0.30)),
            (0.18, color(0.96, 0.45, 0.32)),
            (0.5, color(0.78, 0.27, 0.42)),
            (1, color(0.27, 0.13, 0.36)),
        ])
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: horizon, width: size, height: size - horizon))
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: size), options: [])
        context.restoreGState()

        // The sun, half set, with a soft glow around it.
        let sun = CGPoint(x: size * 0.62, y: horizon + size * 0.015)
        let radius = size * 0.13
        let glow = try gradient([
            (0, color(1, 0.86, 0.55, 0.85)),
            (0.35, color(1, 0.62, 0.35, 0.35)),
            (1, color(1, 0.5, 0.3, 0)),
        ])
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: horizon, width: size, height: size - horizon))
        context.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: size * 0.42, options: [])
        let disc = try gradient([
            (0, color(1, 0.97, 0.82)),
            (0.7, color(1, 0.84, 0.48)),
            (1, color(1, 0.72, 0.38)),
        ])
        context.addEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        context.drawLinearGradient(disc, start: CGPoint(x: 0, y: sun.y + radius), end: CGPoint(x: 0, y: horizon), options: [])
        context.restoreGState()

        // The sea, darkening towards the bottom, with bands of reflected light.
        let sea = try gradient([
            (0, color(0.18, 0.09, 0.26)),
            (0.7, color(0.55, 0.22, 0.36)),
            (1, color(0.86, 0.42, 0.34)),
        ])
        context.drawLinearGradient(sea, start: .zero, end: CGPoint(x: 0, y: horizon), options: [])
        for band in 0 ..< 7 {
            let depth = CGFloat(band) / 7
            let y = horizon - size * (0.03 + depth * 0.3)
            let half = size * (0.13 - depth * 0.08) * (band.isMultiple(of: 2) ? 1 : 0.65)
            let height = size * (0.011 - depth * 0.005)
            context.setFillColor(color(1, 0.8, 0.52, 0.5 - depth * 0.4))
            context.addPath(CGPath(
                roundedRect: CGRect(x: sun.x - half, y: y, width: half * 2, height: height),
                cornerWidth: height / 2, cornerHeight: height / 2, transform: nil
            ))
            context.fillPath()
        }

        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}

/// Values of some keys of the test runner's own defaults (never the app's), put back as
/// they were, or removed when they were not set.
private struct HomeShotDefaults {
    private let values: [String: Any?]

    init(keys: [String]) {
        var values: [String: Any?] = [:]
        for key in keys {
            values[key] = .some(UserDefaults.standard.object(forKey: key))
        }
        self.values = values
    }

    func restore() {
        for (key, value) in values {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
