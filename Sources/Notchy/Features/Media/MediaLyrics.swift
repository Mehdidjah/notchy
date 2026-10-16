import Foundation

/// One line of lyrics; untimed lyrics carry timestamp 0 and `isTimed == false`.
struct MediaLyricLine: Equatable, Sendable {
    var timestamp: TimeInterval
    var text: String
    var isTimed: Bool = true
}

enum MediaLyricsAvailability: Equatable, Sendable {
    case loading
    case timed
    case untimed
    case instrumental
    case unavailable
}

/// The outcome of a lyrics lookup.
struct MediaLyricsResolution: Equatable, Sendable {
    var lines: [MediaLyricLine] = []
    var availability: MediaLyricsAvailability = .unavailable

    static let unavailable = MediaLyricsResolution()
}

/// LRC parsing, LRCLIB result matching and request clean-up, as pure functions.
enum MediaLyricsEngine {
    /// Lines lead the voice by a quarter second so they can be read in time.
    static let leadTime: TimeInterval = 0.25
    /// Gaps shorter than this are breaths, not instrumental breaks.
    static let instrumentalBreakThreshold: TimeInterval = 5

    // MARK: - LRC

    private static let timeTagPattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
    private static let offsetTagPattern = #"\[offset:\s*([+-]?\d+)\s*\]"#

    /// Parses LRC text. A line may carry several time tags (a repeated chorus) and is
    /// emitted once per tag; bare tags are kept as empty lines because they mark where
    /// singing stops. `[offset:±ms]` shifts every line (positive = earlier).
    static func parseLRC(_ lrc: String) -> [MediaLyricLine] {
        guard let regex = try? NSRegularExpression(pattern: timeTagPattern) else { return [] }
        let offset = parseOffset(lrc)
        var lines: [MediaLyricLine] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let textStart = last.range.location + last.range.length
            guard textStart <= line.length else { continue }
            let text = line.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let time = timestamp(match, in: line) else { continue }
                lines.append(MediaLyricLine(timestamp: max(0, time - offset), text: text))
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private static func parseOffset(_ lrc: String) -> TimeInterval {
        guard let regex = try? NSRegularExpression(pattern: offsetTagPattern) else { return 0 }
        let text = lrc as NSString
        guard let match = regex.firstMatch(in: lrc, range: NSRange(location: 0, length: text.length)),
              match.range(at: 1).location != NSNotFound,
              let milliseconds = Double(text.substring(with: match.range(at: 1)))
        else { return 0 }
        return milliseconds / 1000
    }

    private static func timestamp(_ match: NSTextCheckingResult, in line: NSString) -> TimeInterval? {
        guard match.range(at: 1).location != NSNotFound, match.range(at: 2).location != NSNotFound,
              let minutes = Double(line.substring(with: match.range(at: 1))),
              let seconds = Double(line.substring(with: match.range(at: 2)))
        else { return nil }
        var fraction = 0.0
        let fractionRange = match.range(at: 3)
        if fractionRange.location != NSNotFound {
            let digits = line.substring(with: fractionRange)
            if let value = Double(digits) {
                fraction = value / pow(10, Double(digits.count))
            }
        }
        return minutes * 60 + seconds + fraction
    }

    /// Plain lyrics split into untimed lines.
    static func untimedLines(_ plain: String) -> [MediaLyricLine] {
        plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { MediaLyricLine(timestamp: 0, text: $0, isTimed: false) }
    }

    // MARK: - Current line

    /// Index of the last line whose timestamp has been reached, or -1 before the first.
    static func currentIndex(in lines: [MediaLyricLine], at position: TimeInterval) -> Int {
        var index = -1
        for (candidate, line) in lines.enumerated() {
            if position >= line.timestamp { index = candidate } else { break }
        }
        return index
    }

    /// How far through the current line playback is, 0...1, for the sweep highlight.
    static func sweepProgress(in lines: [MediaLyricLine], index: Int, position: TimeInterval, duration: TimeInterval) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let start = lines[index].timestamp
        let end = index + 1 < lines.count ? lines[index + 1].timestamp : max(duration, start + 4)
        guard end > start else { return 1 }
        return min(max((position - start) / (end - start), 0), 1)
    }

    /// Whether playback sits in a stretch without words long enough to mark: a blank line
    /// lasting at least five seconds, or an intro at least that long.
    static func isInstrumentalBreak(lines: [MediaLyricLine], index: Int, duration: TimeInterval) -> Bool {
        guard !lines.isEmpty, lines.contains(where: \.isTimed) else { return false }
        if index < 0 {
            return (lines.first?.timestamp ?? 0) >= instrumentalBreakThreshold
        }
        guard lines.indices.contains(index),
              lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        let end = index + 1 < lines.count ? lines[index + 1].timestamp : duration
        return end - lines[index].timestamp >= instrumentalBreakThreshold
    }

    /// Seconds to sleep before the next line can start, clamped to 50...250 ms.
    static func delayUntilNextLine(in lines: [MediaLyricLine], after position: TimeInterval) -> TimeInterval {
        let next = lines.first { $0.timestamp > position }?.timestamp
        let delay = next.map { $0 - position } ?? 0.25
        return min(max(delay, 0.05), 0.25)
    }

    // MARK: - Request clean-up

    static func normalizedComponent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Strips "(feat. …)", "[ft. …]", "- featuring …" and trailing remaster/live/mono/stereo
    /// tags so the search finds the original recording.
    static func normalizedTitle(_ value: String) -> String {
        var title = normalizedComponent(value)
        let patterns = [
            #"\s*\((feat\.?|ft\.?|featuring)[^\)]*\)"#,
            #"\s*\[(feat\.?|ft\.?|featuring)[^\]]*\]"#,
            #"\s*-\s*(feat\.?|ft\.?|featuring)\s+.*$"#,
            #"\s*\((remaster(ed)?|live|mono|stereo)[^\)]*\)$"#,
            #"\s*\[(remaster(ed)?|live|mono|stereo)[^\]]*\]$"#
        ]
        for pattern in patterns {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return normalizedComponent(title)
    }

    private static let placeholderArtists: Set<String> = [
        "unknown artist", "unknown", "unknown artists", "artist unknown", "no artist", "untitled artist"
    ]
    private static let placeholderTitlePatterns = [
        #"^(audio[ _-]*)?track[ _-]*[0-9]+$"#,
        #"^track$"#,
        #"^untitled[ _-]*[0-9]+$"#,
        #"^unknown([ _-]*track)?([ _-]*[0-9]+)?$"#
    ]

    /// True when the metadata could be any song (placeholder artist, "Track 3"), so any
    /// lyrics found would belong to somebody else. The app's own placeholder metadata counts too.
    static func namesNoParticularTrack(title: String, artist: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if title.isEmpty || artist.isEmpty { return true }
        if placeholderArtists.contains(artist) { return true }
        if !MediaPlaceholder.hasRealMetadata(title: title, artist: artist) { return true }
        return placeholderTitlePatterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - LRCLIB matching

    struct Candidate: Decodable, Equatable, Sendable {
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?

        var carriesSyncedLyrics: Bool {
            !(syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Markers of a different recording than the one asked for (only when absent from the
    /// request, so a sped-up track still finds sped-up lyrics).
    private static let versionMarkers = [
        "karaoke", "instrumental", "sped up", "spedup", "slowed", "nightcore", "remix",
        "re-record", "rerecord", "'s version", "cover", "tribute", "acapella", "a cappella",
        "made popular by", "originally performed by"
    ]

    static func matchingForm(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filters to rows agreeing on title and artist (exact or contained, no unrequested
    /// version marker; instrumental rows only with an exact title and a duration within
    /// 2 s), prefers rows with synced lyrics, then scores title 8/4, artist 8/4,
    /// album 4/2 and synced +3.
    static func bestMatch(in candidates: [Candidate], title: String, artist: String, album: String, duration: TimeInterval) -> Candidate? {
        let title = matchingForm(title)
        let artist = matchingForm(artist)
        let album = matchingForm(album)

        return candidates
            .filter { candidate in
                agrees(candidate, title: title, artist: artist)
                    && (candidate.instrumental != true || isReliableInstrumental(candidate, title: title, duration: duration))
            }
            .max { lhs, rhs in
                if lhs.carriesSyncedLyrics != rhs.carriesSyncedLyrics { return rhs.carriesSyncedLyrics }
                return score(lhs, title: title, artist: artist, album: album) < score(rhs, title: title, artist: artist, album: album)
            }
    }

    static func agrees(_ candidate: Candidate, title: String, artist: String) -> Bool {
        let resultTitle = matchingForm(candidate.trackName ?? "")
        let resultArtist = matchingForm(candidate.artistName ?? "")
        guard overlaps(resultTitle, title), overlaps(resultArtist, artist) else { return false }
        return !carriesUnrequestedVersion(resultTitle, requested: title)
    }

    static func isReliableInstrumental(_ candidate: Candidate, title: String, duration: TimeInterval) -> Bool {
        guard matchingForm(candidate.trackName ?? "") == title else { return false }
        guard duration.isFinite, duration > 0, let candidateDuration = candidate.duration,
              candidateDuration.isFinite, candidateDuration > 0 else { return true }
        return abs(candidateDuration - duration) <= 2
    }

    static func score(_ candidate: Candidate, title: String, artist: String, album: String) -> Int {
        let resultTitle = matchingForm(candidate.trackName ?? "")
        let resultArtist = matchingForm(candidate.artistName ?? "")
        let resultAlbum = matchingForm(candidate.albumName ?? "")
        var score = 0
        if resultTitle == title { score += 8 } else if overlaps(resultTitle, title) { score += 4 }
        if resultArtist == artist { score += 8 } else if overlaps(resultArtist, artist) { score += 4 }
        if !album.isEmpty, !resultAlbum.isEmpty {
            if resultAlbum == album { score += 4 } else if overlaps(resultAlbum, album) { score += 2 }
        }
        if candidate.carriesSyncedLyrics { score += 3 }
        return score
    }

    /// Turns the chosen row into displayable lines.
    static func resolution(for candidate: Candidate) -> MediaLyricsResolution {
        if candidate.instrumental == true {
            return MediaLyricsResolution(lines: [], availability: .instrumental)
        }
        if let synced = candidate.syncedLyrics {
            let lines = parseLRC(synced)
            if lines.contains(where: { !$0.text.isEmpty }) {
                return MediaLyricsResolution(lines: lines, availability: .timed)
            }
        }
        let plain = untimedLines(candidate.plainLyrics ?? "")
        return plain.isEmpty ? .unavailable : MediaLyricsResolution(lines: plain, availability: .untimed)
    }

    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// The result title names a version (karaoke, remix, cover …) the request did not.
    static func carriesUnrequestedVersion(_ resultTitle: String, requested title: String) -> Bool {
        versionMarkers.contains { marker in
            containsWord(resultTitle, marker) && !containsWord(title, marker)
        }
    }

    private static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: "\\b" + NSRegularExpression.escapedPattern(for: needle), options: .regularExpression) != nil
    }
}

/// Second lyrics source: NetEase Cloud Music's public search and lyric endpoints,
/// asked only when LRCLIB has nothing. The player gives no song id, so the track is found
/// again by search and trusted only when its length is within 2 s of the playing one.
enum MediaNetEaseLyrics {
    struct Song: Equatable, Sendable {
        let id: Int
        let name: String
        let artists: [String]
        /// Seconds (NetEase reports milliseconds).
        let duration: TimeInterval
    }

    static let durationTolerance: TimeInterval = 2

    /// `&`, `+`, `=`, `/`, `?` and `#` are structural in a query, so a title carrying one
    /// must have it escaped.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=/?#")
        return allowed
    }()

    static func searchURL(title: String, artist: String) -> URL? {
        // NetEase joins collaborators with "/", which is no use as a search word.
        let query = "\(title) \(artist.replacingOccurrences(of: "/", with: " "))"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        return URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&limit=10")
    }

    /// `lv=-1` asks for the current line-synced lyrics.
    static func lyricURL(songID: Int) -> URL? {
        URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=-1")
    }

    static func parseSearch(_ data: Data) -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]]
        else { return [] }
        return songs.compactMap { song in
            guard let id = song["id"] as? Int, let name = song["name"] as? String else { return nil }
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let milliseconds = (song["duration"] as? Double) ?? 0
            return Song(id: id, name: name, artists: artists, duration: milliseconds / 1000)
        }
    }

    /// `nolyric` marks an instrumental; `uncollected` or an empty body means none.
    static func parseLyrics(_ data: Data) -> MediaLyricsResolution {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unavailable }
        if json["nolyric"] as? Bool == true {
            return MediaLyricsResolution(lines: [], availability: .instrumental)
        }
        guard json["uncollected"] as? Bool != true,
              let lrc = json["lrc"] as? [String: Any],
              let body = (lrc["lyric"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty
        else { return .unavailable }
        let lines = MediaLyricsEngine.parseLRC(body)
        if lines.contains(where: { !$0.text.isEmpty }) {
            return MediaLyricsResolution(lines: lines, availability: .timed)
        }
        let plain = MediaLyricsEngine.untimedLines(body)
        return plain.isEmpty ? .unavailable : MediaLyricsResolution(lines: plain, availability: .untimed)
    }

    /// Filter, then rank: title and one of the artists must agree, no unrequested version,
    /// length within 2 s when both are known; then title 8/4, artist 8/4, closer length.
    static func bestMatch(in songs: [Song], title: String, artist: String, duration: TimeInterval) -> Song? {
        let title = MediaLyricsEngine.matchingForm(title)
        let artist = MediaLyricsEngine.matchingForm(artist)
        return songs
            .filter { agrees($0, title: title, artist: artist, duration: duration) }
            .max { lhs, rhs in
                let left = score(lhs, title: title, artist: artist)
                let right = score(rhs, title: title, artist: artist)
                if left != right { return left < right }
                return abs(lhs.duration - duration) > abs(rhs.duration - duration)
            }
    }

    static func agrees(_ song: Song, title: String, artist: String, duration: TimeInterval) -> Bool {
        let songTitle = MediaLyricsEngine.matchingForm(song.name)
        guard MediaLyricsEngine.overlaps(songTitle, title),
              !MediaLyricsEngine.carriesUnrequestedVersion(songTitle, requested: title)
        else { return false }
        let artists = song.artists.map(MediaLyricsEngine.matchingForm)
        guard artists.contains(where: { MediaLyricsEngine.overlaps($0, artist) }) else { return false }
        guard duration > 0, song.duration > 0 else { return true }
        return abs(song.duration - duration) <= durationTolerance
    }

    static func score(_ song: Song, title: String, artist: String) -> Int {
        let songTitle = MediaLyricsEngine.matchingForm(song.name)
        let artists = song.artists.map(MediaLyricsEngine.matchingForm)
        var score = 0
        if songTitle == title { score += 8 } else if MediaLyricsEngine.overlaps(songTitle, title) { score += 4 }
        if artists.joined(separator: "/") == artist || artists == [artist] {
            score += 8
        } else if artists.contains(where: { MediaLyricsEngine.overlaps($0, artist) }) {
            score += 4
        }
        return score
    }
}

/// LRCLIB lookups with a NetEase fallback and an 80-entry cache that never stores a miss.
actor MediaLyricsProvider {
    static let shared = MediaLyricsProvider()

    private let session: URLSession
    private var cache: [String: MediaLyricsResolution] = [:]
    private var order: [String] = []
    private static let cacheLimit = 80

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func lyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> MediaLyricsResolution {
        let requestTitle = MediaLyricsEngine.normalizedTitle(title)
        let requestArtist = MediaLyricsEngine.normalizedComponent(artist)
        let requestAlbum = MediaLyricsEngine.normalizedComponent(album)
        guard !MediaLyricsEngine.namesNoParticularTrack(title: requestTitle, artist: requestArtist) else {
            return .unavailable
        }

        let key = [requestTitle, requestArtist, requestAlbum, String(Int(duration.rounded()))]
            .map { $0.lowercased() }
            .joined(separator: "|")
        if let cached = cache[key] { return cached }

        let foldedTitle = requestTitle.folding(options: .diacriticInsensitive, locale: .current)
        let foldedArtist = requestArtist.folding(options: .diacriticInsensitive, locale: .current)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: foldedTitle),
            URLQueryItem(name: "artist_name", value: foldedArtist)
        ]
        guard let url = components.url else { return .unavailable }

        var request = URLRequest(url: url)
        request.setValue("Notchy (https://github.com)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        var resolution = MediaLyricsResolution.unavailable
        if let (data, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let candidates = try? JSONDecoder().decode([MediaLyricsEngine.Candidate].self, from: data),
           let best = MediaLyricsEngine.bestMatch(
               in: candidates, title: foldedTitle, artist: foldedArtist, album: requestAlbum, duration: duration) {
            resolution = MediaLyricsEngine.resolution(for: best)
        }
        // A failed or empty LRCLIB answer still leaves NetEase to ask.
        if resolution.availability == .unavailable, !Task.isCancelled {
            resolution = await netEaseLyrics(title: requestTitle, artist: requestArtist, duration: duration)
        }

        if resolution.availability != .unavailable {
            if cache[key] == nil {
                order.append(key)
                while order.count > Self.cacheLimit {
                    cache.removeValue(forKey: order.removeFirst())
                }
            }
            cache[key] = resolution
        }
        return resolution
    }

    private func netEaseLyrics(title: String, artist: String, duration: TimeInterval) async -> MediaLyricsResolution {
        guard let searchURL = MediaNetEaseLyrics.searchURL(title: title, artist: artist),
              let (searchData, searchResponse) = try? await session.data(from: searchURL),
              (searchResponse as? HTTPURLResponse)?.statusCode == 200,
              let song = MediaNetEaseLyrics.bestMatch(
                in: MediaNetEaseLyrics.parseSearch(searchData), title: title, artist: artist, duration: duration),
              let lyricURL = MediaNetEaseLyrics.lyricURL(songID: song.id),
              let (lyricData, lyricResponse) = try? await session.data(from: lyricURL),
              (lyricResponse as? HTTPURLResponse)?.statusCode == 200
        else { return .unavailable }
        return MediaNetEaseLyrics.parseLyrics(lyricData)
    }
}
