import Foundation
import SwiftUI

/// Repeat state as the players report it. Raw values are
/// off 1, one 2, all 3.
enum MediaRepeatMode: Int, Codable, Sendable {
    case off = 1
    case one = 2
    case all = 3
}

/// A player Notchy can read and drive through AppleScript.
enum MediaSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case spotify

    var id: Self { self }

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// The name AppleScript addresses the application by.
    var scriptingName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    /// The player's own colour, used for active shuffle, repeat and favourite buttons.
    var brandAccent: Color {
        switch self {
        case .appleMusic: Color(red: 0.999, green: 0.171, blue: 0.331)
        case .spotify: Color(red: 0.0, green: 0.857, blue: 0.302)
        }
    }

    init?(bundleIdentifier: String?) {
        guard let match = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        self = match
    }
}

/// Which player the notch follows.
enum MediaSourcePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Whichever supported player is playing; the last one used while both are paused.
    case automatic
    case appleMusic
    case spotify

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    var allowedSources: [MediaSourceKind] {
        switch self {
        case .automatic: MediaSourceKind.allCases
        case .appleMusic: [.appleMusic]
        case .spotify: [.spotify]
        }
    }
}

/// One reading of a player, taken by an AppleScript round trip.
struct MediaPlaybackSnapshot: Equatable, Sendable {
    var source: MediaSourceKind
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    /// Player position in seconds at `lastUpdated`.
    var position: Double
    /// Track length in seconds; 0 when the player reports none.
    var duration: Double
    var playbackRate: Double = 1
    var isShuffled: Bool
    var repeatMode: MediaRepeatMode
    /// Stable identity of the track inside the player (Music persistent ID, Spotify URI).
    var trackIdentifier: String?
    /// Spotify only: where the cover can be downloaded from.
    var artworkURL: String?
    /// Encoded cover image, when one has been loaded for this track.
    var artworkData: Data?
    var lastUpdated: Date

    /// Spotify plays adverts as tracks whose URI is `spotify:ad:…`; they never trigger a
    /// sneak peek or a lyrics lookup.
    var isAdvertisement: Bool {
        guard source == .spotify, let trackIdentifier else { return false }
        return trackIdentifier.hasPrefix("spotify:ad:") || trackIdentifier.contains("/ad/")
    }

    /// Identifies the artwork this reading belongs to, so a slow download is never
    /// applied to the next track.
    var artworkKey: String {
        if let trackIdentifier, !trackIdentifier.isEmpty {
            return "\(source.rawValue)|\(trackIdentifier)"
        }
        return "\(source.rawValue)|\(title)|\(artist)|\(album)"
    }
}

/// Placeholder metadata: shown while nothing has played, never counted as a session.
enum MediaPlaceholder {
    static let title = "I'm Handsome"
    static let artist = "Me"
    static let album = "Self Love"

    private static let titles: Set<String> = ["i'm handsome", "unknown", "not playing"]
    private static let artists: Set<String> = ["me", "unknown"]

    /// Whether the metadata names a real track rather than a placeholder.
    static func hasRealMetadata(title: String, artist: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let realTitle = !normalizedTitle.isEmpty && !titles.contains(normalizedTitle)
        let realArtist = !normalizedArtist.isEmpty && !artists.contains(normalizedArtist)
        return realTitle || realArtist
    }

    /// `hasActiveSession`: playing, or paused on a real track.
    static func hasActiveSession(isPlaying: Bool, title: String, artist: String) -> Bool {
        isPlaying || hasRealMetadata(title: title, artist: artist)
    }
}

/// What a skip button or a horizontal swipe does.
enum MediaSkipBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case track
    case tenSecond

    var id: Self { self }

    var displayName: String {
        switch self {
        case .track: "Track Skip"
        case .tenSecond: "±10 Seconds"
        }
    }

    var explanation: String {
        switch self {
        case .track: "Standard previous/next track controls"
        case .tenSecond: "Skip forward or backward by ten seconds"
        }
    }
}

/// Colour of the filled part of the progress slider.
enum MediaSliderColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case white
    case albumArt
    case accent

    var id: Self { self }

    var label: String {
        switch self {
        case .white: "White"
        case .albumArt: "Match album art"
        case .accent: "Accent color"
        }
    }
}

/// How the artwork colours are derived.
enum MediaColorExtractionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Plain average, with its complementary hue as the secondary colour.
    case legacy
    /// Dominant saturated hue bucket, with an opposing bucket as the secondary colour.
    case vibrant

    var id: Self { self }

    var label: String {
        switch self {
        case .legacy: "Legacy"
        case .vibrant: "Vibrant"
        }
    }
}

/// One of the five configurable control slots under the open player.
enum MediaControlSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case shuffle
    case trackBackward
    case playPause
    case trackForward
    case repeatMode
    case mediaOutput
    case airPlay
    case lyrics
    case likeTrack
    case seekBackward
    case seekForward
    case none

    static let slotCount = 5

    static let defaultLayout: [MediaControlSlot] = [.shuffle, .trackBackward, .playPause, .trackForward, .repeatMode]
    static let minimalLayout: [MediaControlSlot] = [.none, .trackBackward, .playPause, .trackForward, .none]
    static let tenSecondLayout: [MediaControlSlot] = [.none, .seekBackward, .playPause, .seekForward, .none]

    /// Options offered by the slot pickers, in palette order, then the empty slot.
    static let pickerOptions: [MediaControlSlot] = [
        .trackBackward, .playPause, .trackForward, .seekBackward, .seekForward,
        .shuffle, .repeatMode, .lyrics, .likeTrack, .mediaOutput, .airPlay, .none
    ]

    var id: Self { self }

    var label: String {
        switch self {
        case .shuffle: "Shuffle"
        case .trackBackward: "Previous Track"
        case .playPause: "Play / Pause"
        case .trackForward: "Next Track"
        case .repeatMode: "Repeat"
        case .mediaOutput: "Change Media Output"
        case .airPlay: "AirPlay"
        case .lyrics: "Lyrics"
        case .likeTrack: "Favorite Song"
        case .seekBackward: "Rewind 10s"
        case .seekForward: "Forward 10s"
        case .none: "Empty Slot"
        }
    }

    var iconName: String {
        switch self {
        case .shuffle: "shuffle"
        case .trackBackward: "backward.fill"
        case .playPause: "playpause"
        case .trackForward: "forward.fill"
        case .repeatMode: "repeat"
        case .mediaOutput: "speaker.wave.2"
        case .airPlay: "airplayaudio"
        case .lyrics: "quote.bubble"
        case .likeTrack: "heart"
        case .seekBackward: "gobackward.10"
        case .seekForward: "goforward.10"
        case .none: ""
        }
    }

    /// AirPlay routing is read from Music's own dictionary, so it only exists there.
    var isAppleMusicExclusive: Bool { self == .airPlay }
}

extension Array where Element == MediaControlSlot {
    /// Exactly five slots. A slot the current setup cannot serve becomes empty:
    /// the output picker while "Change Media Output" is off, AirPlay unless Music is the
    /// source, and favouriting when the source cannot do it.
    func normalizedSlots(
        canFavorite: Bool,
        allowsMediaOutput: Bool = true,
        isAppleMusicActive: Bool = true
    ) -> [MediaControlSlot] {
        var slots = map { slot -> MediaControlSlot in
            if slot == .likeTrack && !canFavorite { return .none }
            if slot == .mediaOutput && !allowsMediaOutput { return .none }
            if slot.isAppleMusicExclusive && !isAppleMusicActive { return .none }
            return slot
        }
        if slots.count < MediaControlSlot.slotCount {
            slots += Array(repeating: .none, count: MediaControlSlot.slotCount - slots.count)
        }
        return Array(slots.prefix(MediaControlSlot.slotCount))
    }
}

/// How the line being sung is picked out in the lyrics panel.
enum MediaLyricHighlightStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case sweep
    case gradient
    case solid

    var id: Self { self }

    var label: String {
        switch self {
        case .sweep: "Sweep"
        case .gradient: "Gradient"
        case .solid: "Solid"
        }
    }

    var explanation: String {
        switch self {
        case .sweep: "The highlight travels across the line word by word, in reading order."
        case .gradient: "The current line is lit by one fixed gradient that does not move, the way lyrics were marked before the sweep."
        case .solid: "The current line is lit in one flat colour, with nothing crossing it."
        }
    }
}

/// How a track change is announced on the closed notch.
enum MediaSneakPeekStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A grey "Title - Artist" line under the notch for 1.5 s.
    case standard
    /// The closed notch widens to 380 pt for 3 s, title left of the notch, artist right.
    case inline

    var id: Self { self }

    var label: String {
        switch self {
        case .standard: "Default"
        case .inline: "Inline"
        }
    }
}

/// Pure playback-position arithmetic shared by the slider, the lyrics and the tests.
enum MediaPlaybackMath {
    /// Anchor + rate extrapolation, clamped to the track.
    static func estimatedPosition(
        elapsed: TimeInterval,
        anchor: Date,
        rate: Double,
        isPlaying: Bool,
        duration: TimeInterval,
        at date: Date
    ) -> TimeInterval {
        guard isPlaying else { return min(elapsed, max(duration, 0)) }
        let estimate = elapsed + date.timeIntervalSince(anchor) * rate
        return min(max(0, estimate), max(duration, 0))
    }

    /// A duration a track could actually have (finite, positive, at most a day).
    static func isUsableDuration(_ duration: Double) -> Bool {
        duration.isFinite && duration > 0 && duration <= 24 * 60 * 60
    }

    static let unknownTime = "--:--"

    /// "m:ss", or "h:mm:ss" past an hour; "--:--" for anything that is not a time.
    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return unknownTime }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Optimistic play/pause expectation: events contradicting the expected state are
/// ignored until the player confirms it or the recovery timeout cancels the expectation.
struct MediaOptimisticPlayback: Sendable {
    private(set) var expectedState: Bool?

    mutating func begin(expecting state: Bool) {
        expectedState = state
    }

    /// Whether an incoming play-state reading should be applied.
    mutating func shouldApply(eventIsPlaying: Bool) -> Bool {
        guard let expectedState else { return true }
        guard eventIsPlaying == expectedState else { return false }
        self.expectedState = nil
        return true
    }

    mutating func cancel(ifExpecting state: Bool) -> Bool {
        guard expectedState == state else { return false }
        expectedState = nil
        return true
    }
}

/// Live-stream heuristic: a playing track with no known duration for three
/// readings, or one that keeps sitting at its end, is treated as a stream.
struct MediaLiveStreamDetector: Sendable {
    private var unknownDurationCount = 0
    private var edgeCount = 0
    private var completionCount = 0
    private var releaseCount = 0
    private(set) var isLive = false

    mutating func reset() {
        self = MediaLiveStreamDetector()
    }

    mutating func observe(isPlaying: Bool, position: Double, duration: Double) {
        let knownDuration = duration.isFinite && duration > 0
        if knownDuration {
            unknownDurationCount = 0
            let current = max(0, min(position, duration))
            let remaining = duration - position
            let complete = isPlaying && current / duration >= 0.999
            let nearEdge = isPlaying && remaining.isFinite && remaining <= 1 && current >= 10

            if complete {
                completionCount = min(completionCount + 1, 8)
                releaseCount = 0
            } else {
                releaseCount = min(releaseCount + 1, 8)
                completionCount = max(completionCount - 1, 0)
            }
            if nearEdge || complete {
                edgeCount = min(edgeCount + 1, 12)
            } else {
                edgeCount = max(edgeCount - 1, 0)
            }

            if !isLive {
                if completionCount >= 3 || edgeCount >= 5 { isLive = true }
            } else if (duration > 10 && remaining > 5)
                || (completionCount == 0 && edgeCount == 0 && releaseCount >= 4) {
                isLive = false
            }
        } else if isPlaying {
            edgeCount = max(edgeCount - 1, 0)
            completionCount = max(completionCount - 1, 0)
            releaseCount = 0
            unknownDurationCount = min(unknownDurationCount + 1, 8)
            if unknownDurationCount >= 3 { isLive = true }
        } else {
            unknownDurationCount = 0
            edgeCount = 0
            completionCount = 0
            releaseCount = 0
        }
    }
}
