import Foundation

/// Network lookups for the player: catalogue artwork for streamed Music tracks, Spotify
/// cover downloads and the explicit flag. All public HTTPS (iTunes Search API and the
/// players' own artwork URLs).
actor MediaArtworkResolver {
    static let shared = MediaArtworkResolver()

    private let session: URLSession
    /// Only the most recent catalogue hit is kept: refreshes ask for the same track again
    /// and again, and older covers would only hold memory.
    private var catalogKey: String?
    private var catalogData: Data?
    private var downloadURL: String?
    private var downloadData: Data?
    private var explicitCache: [String: Bool] = [:]
    private var explicitOrder: [String] = []
    private static let explicitCacheLimit = 300

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    // MARK: - Artwork

    /// Cover from the iTunes catalogue for a Music track that has no embedded artwork.
    func catalogArtwork(title: String, artist: String, album: String) async -> Data? {
        let key = "\(title)|\(artist)|\(album)"
        if key == catalogKey, let catalogData { return catalogData }
        guard let url = Self.searchURL(term: "\(title) \(artist)", limit: 10) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let match = Self.bestArtworkMatch(in: response.results, title: title, album: album),
                  let small = match.artworkUrl100,
                  let imageURL = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600"))
            else { return nil }
            let (imageData, _) = try await session.data(from: imageURL)
            guard imageData.count > MediaScripting.minimumArtworkBytes else { return nil }
            catalogKey = key
            catalogData = imageData
            return imageData
        } catch {
            return nil
        }
    }

    /// Downloads a cover from a URL a player handed out; the last one is kept.
    func artwork(from urlString: String) async -> Data? {
        if urlString == downloadURL, let downloadData { return downloadData }
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) { return nil }
            guard data.count > MediaScripting.minimumArtworkBytes else { return nil }
            downloadURL = urlString
            downloadData = data
            return data
        } catch {
            return nil
        }
    }

    /// Prefers a result matching title and album, then album, then title, then the first.
    static func bestArtworkMatch(in results: [SearchTrack], title: String, album: String) -> SearchTrack? {
        let title = title.lowercased()
        let album = album.lowercased()
        return results.first { $0.trackName?.lowercased() == title && $0.collectionName?.lowercased() == album }
            ?? results.first { $0.collectionName?.lowercased() == album }
            ?? results.first { $0.trackName?.lowercased() == title }
            ?? results.first
    }

    // MARK: - Explicit flag

    /// Whether the iTunes catalogue marks the track explicit; false when unsure.
    func isExplicit(title: String, artist: String, album: String) async -> Bool {
        let key = [title, artist, album].map(Self.normalize).joined(separator: "|")
        guard !Self.normalize(title).isEmpty, !Self.normalize(artist).isEmpty else { return false }
        if let cached = explicitCache[key] { return cached }
        guard let url = Self.searchURL(term: "\(title) \(artist)", limit: 15) else { return false }

        var value = false
        if let (data, _) = try? await session.data(from: url),
           let response = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            let scored = response.results.map { ($0, Self.explicitMatchScore($0, title: title, artist: artist, album: album)) }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 8 {
                value = best.0.trackExplicitness?.trimmingCharacters(in: .whitespaces).lowercased() == "explicit"
            }
        }
        if explicitCache[key] == nil {
            explicitOrder.append(key)
            while explicitOrder.count > Self.explicitCacheLimit {
                explicitCache.removeValue(forKey: explicitOrder.removeFirst())
            }
        }
        explicitCache[key] = value
        return value
    }

    /// Title 6 exact / 4 contained (else no match), artist 4 / 2, album 2 / 1; 8 is a match.
    static func explicitMatchScore(_ track: SearchTrack, title: String, artist: String, album: String) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        let wantedTitle = canonicalTitle(title)
        guard !trackTitle.isEmpty, !wantedTitle.isEmpty else { return Int.min }

        var score: Int
        if trackTitle == wantedTitle {
            score = 6
        } else if trackTitle.contains(wantedTitle) || wantedTitle.contains(trackTitle) {
            score = 4
        } else {
            return Int.min
        }

        let trackArtist = normalize(track.artistName ?? "")
        let wantedArtist = normalize(artist)
        if !wantedArtist.isEmpty {
            if trackArtist == wantedArtist {
                score += 4
            } else if !trackArtist.isEmpty && (trackArtist.contains(wantedArtist) || wantedArtist.contains(trackArtist)) {
                score += 2
            }
        }

        let trackAlbum = normalize(track.collectionName ?? "")
        let wantedAlbum = normalize(album)
        if !wantedAlbum.isEmpty {
            if trackAlbum == wantedAlbum {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(wantedAlbum) || wantedAlbum.contains(trackAlbum)) {
                score += 1
            }
        }
        return score
    }

    static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchURL(term: String, limit: Int) -> URL? {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return components.url
    }

    struct SearchResponse: Decodable, Sendable {
        let results: [SearchTrack]
    }

    struct SearchTrack: Decodable, Sendable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let trackExplicitness: String?
    }
}
