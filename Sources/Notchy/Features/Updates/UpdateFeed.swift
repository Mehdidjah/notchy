import Foundation

/// A published version of Notchy and where to get it.
struct UpdateRelease: Equatable, Sendable {
    var version: AppVersion
    var title: String
    var notes: String
    /// The release's web page.
    var pageURL: URL
    /// The disk image to download, when the release has one.
    var downloadURL: URL?
    var publishedAt: Date?

    /// What the Download button opens: the disk image, or the release page without one.
    var preferredDownloadURL: URL { downloadURL ?? pageURL }
}

/// Where the update check learns about the newest release.
protocol UpdateFeed: Sendable {
    /// The newest published release, or nil when nothing has been published yet.
    func latestRelease() async throws -> UpdateRelease?
}

enum UpdateFeedError: LocalizedError, Equatable {
    case badResponse(statusCode: Int)
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .badResponse(let code) where code == 403 || code == 429:
            "The release server is limiting requests. Try again later."
        case .badResponse(let code):
            "The release server answered with status \(code)."
        case .invalidRelease:
            "The newest release has no readable version number."
        }
    }
}

/// Reads the latest release of a public GitHub repository through the REST API. Drafts and
/// pre-releases are never returned as "latest".
struct GitHubReleaseFeed: UpdateFeed {
    let repository: String
    var userAgent = "Notchy"
    var session: URLSession = .shared

    /// `owner/name`, each made of letters, digits, `.`, `-` or `_`.
    static func isValidRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
        }
    }

    func latestRelease() async throws -> UpdateRelease? {
        guard Self.isValidRepository(repository),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateFeedError.invalidRelease
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw UpdateFeedError.badResponse(statusCode: status) }
        return try Self.decodeRelease(from: data)
    }

    static func decodeRelease(from data: Data) throws -> UpdateRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard let version = AppVersion(payload.tagName), let pageURL = URL(string: payload.htmlURL) else {
            throw UpdateFeedError.invalidRelease
        }
        let image = (payload.assets ?? []).first { $0.name.lowercased().hasSuffix(".dmg") }
        let title = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return UpdateRelease(
            version: version,
            title: title.isEmpty ? "Notchy \(version)" : title,
            notes: payload.body ?? "",
            pageURL: pageURL,
            downloadURL: image.flatMap { URL(string: $0.browserDownloadURL) },
            publishedAt: payload.publishedAt
        )
    }

    private struct Payload: Decodable {
        var tagName: String
        var name: String?
        var body: String?
        var htmlURL: String
        var publishedAt: Date?
        var assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, body, htmlURL = "html_url", publishedAt = "published_at", assets
        }
    }

    private struct Asset: Decodable {
        var name: String
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url"
        }
    }
}
