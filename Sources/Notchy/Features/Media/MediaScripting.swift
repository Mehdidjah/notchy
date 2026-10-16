import AppKit
import Foundation

/// Runs AppleScript on one private serial queue.
///
/// `NSAppleScript` is not safe to use from several threads at once, and a script that
/// talks to a busy player can block for a while, so every script goes through this queue,
/// never the main thread. Only parsed, `Sendable` values leave the queue.
enum MediaAppleScript {
    private static let queue = DispatchQueue(label: "Notchy.media.applescript", qos: .userInitiated)
    /// Compiled scripts reused across calls. Touched only on `queue`.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    /// Executes `source` and parses the reply on the script queue.
    static func evaluate<T: Sendable>(
        _ source: String,
        cache: Bool = false,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let script = script(for: source, cache: cache) else {
                    continuation.resume(returning: nil)
                    return
                }
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? parse(descriptor) : nil)
            }
        }
    }

    /// Executes a command, returning whether it ran without an AppleScript error.
    @discardableResult
    static func run(_ source: String) async -> Bool {
        await evaluate(source) { _ in true } ?? false
    }

    private static func script(for source: String, cache: Bool) -> NSAppleScript? {
        if cache, let existing = compiled[source] { return existing }
        guard let script = NSAppleScript(source: source) else { return nil }
        if cache {
            var error: NSDictionary?
            script.compileAndReturnError(&error)
            compiled[source] = script
        }
        return script
    }
}

/// A transport command for a player.
enum MediaCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(TimeInterval)
    case toggleShuffle
    case cycleRepeat
}

/// AppleScript dictionaries of Music and Spotify: reading the player and sending commands.
enum MediaScripting {
    /// Minimum byte count for artwork to count as an image rather than an empty descriptor.
    static let minimumArtworkBytes = 16

    /// Whether the player is running. Scripting one that is not would launch it.
    static func isRunning(_ source: MediaSourceKind) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    /// Reads the player's state, or nil when it is not running or did not answer.
    static func fetchSnapshot(for source: MediaSourceKind) async -> MediaPlaybackSnapshot? {
        guard isRunning(source) else { return nil }
        switch source {
        case .appleMusic:
            return await MediaAppleScript.evaluate(appleMusicInfoScript, cache: true) { descriptor in
                parseAppleMusic(descriptor, at: Date())
            }
        case .spotify:
            return await MediaAppleScript.evaluate(spotifyInfoScript, cache: true) { descriptor in
                parseSpotify(descriptor, at: Date())
            }
        }
    }

    /// Raw cover bytes of the current Music track, when the library has them.
    static func fetchAppleMusicArtwork() async -> Data? {
        guard isRunning(.appleMusic) else { return nil }
        return await MediaAppleScript.evaluate(appleMusicArtworkScript, cache: true) { descriptor in
            let data = descriptor.data
            return data.count > minimumArtworkBytes ? data : nil
        }
    }

    /// Music's favourite flag for the current track; nil when Music cannot say.
    static func fetchAppleMusicFavorite() async -> Bool? {
        guard isRunning(.appleMusic) else { return nil }
        for property in favoriteProperties {
            let value: Bool? = await MediaAppleScript.evaluate(
                "tell application \"Music\" to return \(property) of current track", cache: true
            ) { descriptor in
                descriptor.booleanValue
            }
            if let value { return value }
        }
        return nil
    }

    /// Sets Music's favourite flag; false when neither property name is understood.
    static func setAppleMusicFavorite(_ favorite: Bool) async -> Bool {
        guard isRunning(.appleMusic) else { return false }
        for property in favoriteProperties {
            let script = "tell application \"Music\" to set \(property) of current track to \(favorite)"
            if await MediaAppleScript.run(script) { return true }
        }
        return false
    }

    /// Sends `command` to the player. A player that is not running is only launched when
    /// the user asked for it (`launchIfNeeded`), never by background refreshes.
    @discardableResult
    static func perform(_ command: MediaCommand, on source: MediaSourceKind, launchIfNeeded: Bool = false) async -> Bool {
        guard launchIfNeeded || isRunning(source) else { return false }
        return await MediaAppleScript.run(script(for: command, on: source))
    }

    static func script(for command: MediaCommand, on source: MediaSourceKind) -> String {
        let target = "tell application \"\(source.scriptingName)\" to "
        switch command {
        case .play: return target + "play"
        case .pause: return target + "pause"
        case .togglePlayPause: return target + "playpause"
        case .nextTrack: return target + "next track"
        case .previousTrack: return target + "previous track"
        case .seek(let time):
            let seconds = max(0, time.isFinite ? time : 0)
            return target + "set player position to " + String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        case .toggleShuffle:
            switch source {
            case .appleMusic: return target + "set shuffle enabled to not shuffle enabled"
            case .spotify: return target + "set shuffling to not shuffling"
            }
        case .cycleRepeat:
            switch source {
            case .appleMusic:
                // Music cycles off → all → one → off, like its own button.
                return """
                tell application "Music"
                    if song repeat is off then
                        set song repeat to all
                    else if song repeat is all then
                        set song repeat to one
                    else
                        set song repeat to off
                    end if
                end tell
                """
            case .spotify:
                return target + "set repeating to not repeating"
            }
        }
    }

    // MARK: - Parsing

    /// Reads Music's reply: {playing, name, artist, album, position, duration, shuffle,
    /// repeat (1 off / 2 one / 3 all), persistent ID}.
    static func parseAppleMusic(_ descriptor: NSAppleEventDescriptor, at date: Date) -> MediaPlaybackSnapshot? {
        guard descriptor.numberOfItems >= 8 else { return nil }
        let repeatValue = Int(descriptor.atIndex(8)?.int32Value ?? 1)
        let identifier = descriptor.numberOfItems >= 9 ? descriptor.atIndex(9)?.stringValue : nil
        return MediaPlaybackSnapshot(
            source: .appleMusic,
            isPlaying: descriptor.atIndex(1)?.booleanValue ?? false,
            title: descriptor.atIndex(2)?.stringValue ?? "Unknown",
            artist: descriptor.atIndex(3)?.stringValue ?? "Unknown",
            album: descriptor.atIndex(4)?.stringValue ?? "Unknown",
            position: finite(descriptor.atIndex(5)?.doubleValue),
            duration: finite(descriptor.atIndex(6)?.doubleValue),
            isShuffled: descriptor.atIndex(7)?.booleanValue ?? false,
            repeatMode: MediaRepeatMode(rawValue: repeatValue) ?? .off,
            trackIdentifier: identifier.flatMap { $0.isEmpty ? nil : $0 },
            lastUpdated: date
        )
    }

    /// Reads Spotify's reply: {playing, name, artist, album, position, duration (ms),
    /// shuffling, repeating, artwork url, id, spotify url}.
    static func parseSpotify(_ descriptor: NSAppleEventDescriptor, at date: Date) -> MediaPlaybackSnapshot? {
        guard descriptor.numberOfItems >= 11 else { return nil }
        let artworkURL = descriptor.atIndex(9)?.stringValue ?? ""
        let identifier = (descriptor.atIndex(10)?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaPlaybackSnapshot(
            source: .spotify,
            isPlaying: descriptor.atIndex(1)?.booleanValue ?? false,
            title: descriptor.atIndex(2)?.stringValue ?? "Unknown",
            artist: descriptor.atIndex(3)?.stringValue ?? "Unknown",
            album: descriptor.atIndex(4)?.stringValue ?? "Unknown",
            position: finite(descriptor.atIndex(5)?.doubleValue),
            duration: finite(descriptor.atIndex(6)?.doubleValue) / 1000,
            isShuffled: descriptor.atIndex(7)?.booleanValue ?? false,
            repeatMode: (descriptor.atIndex(8)?.booleanValue ?? false) ? .all : .off,
            trackIdentifier: identifier.isEmpty ? nil : identifier,
            artworkURL: artworkURL.isEmpty ? nil : artworkURL,
            lastUpdated: date
        )
    }

    private static func finite(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value
    }

    /// `favorited` replaced `loved` in recent Music versions; the older name still compiles
    /// on macOS 14.
    private static let favoriteProperties = ["favorited", "loved"]

    // Each read is bounded so a hung player cannot hold the script queue for AppleScript's
    // two-minute default; a timeout (-1712) is re-raised so it reads as "no answer" rather
    // than as "nothing playing".

    private static let appleMusicInfoScript = """
    tell application "Music"
        with timeout of 4 seconds
            try
                set nowPlaying to (player state is playing)
                set theTrack to current track
                set repeatSetting to song repeat
                set repeatNumber to 1
                if repeatSetting is one then
                    set repeatNumber to 2
                else if repeatSetting is all then
                    set repeatNumber to 3
                end if
                set trackID to ""
                try
                    set trackID to persistent ID of theTrack
                end try
                return {nowPlaying, name of theTrack, artist of theTrack, album of theTrack, player position, duration of theTrack, shuffle enabled, repeatNumber, trackID}
            on error errorText number errorNumber
                if errorNumber is -1712 then error errorText number errorNumber
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 1, ""}
            end try
        end timeout
    end tell
    """

    private static let appleMusicArtworkScript = """
    tell application "Music"
        with timeout of 4 seconds
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end timeout
    end tell
    """

    private static let spotifyInfoScript = """
    tell application "Spotify"
        with timeout of 4 seconds
            try
                set nowPlaying to (player state is playing)
                set theTrack to current track
                return {nowPlaying, name of theTrack, artist of theTrack, album of theTrack, player position, duration of theTrack, shuffling, repeating, artwork url of theTrack, id of theTrack, spotify url of theTrack}
            on error errorText number errorNumber
                if errorNumber is -1712 then error errorText number errorNumber
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, "", "", ""}
            end try
        end timeout
    end tell
    """
}
