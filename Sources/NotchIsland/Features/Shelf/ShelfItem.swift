import Foundation

/// What a shelf tile holds: a file on disk (kept as a bookmark so renames and moves
/// survive), a snippet of text, or a web link.
enum ShelfItemKind: Codable, Equatable, Hashable, Sendable {
    case file(bookmark: Data)
    case text(String)
    case link(URL)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Tag: String, Codable {
        case file
        case text
        case link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .type) {
        case .file:
            self = .file(bookmark: try container.decode(Data.self, forKey: .value))
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let bookmark):
            try container.encode(Tag.file, forKey: .type)
            try container.encode(bookmark, forKey: .value)
        case .text(let string):
            try container.encode(Tag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(Tag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        }
    }

    /// Symbol drawn on the tile when there is no file to thumbnail.
    var symbolName: String {
        switch self {
        case .file: "doc"
        case .text: "text.justify.left"
        case .link: "link"
        }
    }
}

/// One tile on the shelf.
struct ShelfItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    /// True for files the shelf wrote itself (dropped text, images or raw data). They are
    /// deleted again when the item leaves the shelf.
    var isTemporary: Bool
    /// Path captured when the file was added, so names, dedupe and drag-out never have to
    /// resolve the bookmark on the main actor.
    var cachedPath: String?
    var cachedDisplayName: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        kind: ShelfItemKind,
        isTemporary: Bool = false,
        cachedPath: String? = nil,
        cachedDisplayName: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
        self.cachedPath = cachedPath
        self.cachedDisplayName = cachedDisplayName
        self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, isTemporary, cachedPath, cachedDisplayName, addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ShelfItemKind.self, forKey: .kind)
        isTemporary = try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
        cachedPath = try container.decodeIfPresent(String.self, forKey: .cachedPath)
        cachedDisplayName = try container.decodeIfPresent(String.self, forKey: .cachedDisplayName)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    // MARK: Factories

    /// A file tile. Fails when the URL is not a reachable file, so a bad drop never lands.
    static func file(at url: URL, isTemporary: Bool = false) throws -> ShelfItem {
        let standardized = url.standardizedFileURL
        let bookmark = try ShelfBookmark(fileURL: standardized)
        let name = (try? standardized.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? standardized.lastPathComponent
        return ShelfItem(
            kind: .file(bookmark: bookmark.data),
            isTemporary: isTemporary,
            cachedPath: standardized.path,
            cachedDisplayName: name
        )
    }

    static func text(_ string: String) -> ShelfItem {
        ShelfItem(kind: .text(string))
    }

    static func link(_ url: URL) -> ShelfItem {
        ShelfItem(kind: .link(url))
    }

    // MARK: Derived values

    var isFile: Bool {
        if case .file = kind { return true }
        return false
    }

    /// The file behind a file tile without touching the disk when the path is cached. Falls
    /// back to a bookmark resolve that never tries to mount a volume.
    var fileURL: URL? {
        guard case .file(let bookmark) = kind else { return nil }
        if let cachedPath, !cachedPath.isEmpty {
            return URL(fileURLWithPath: cachedPath)
        }
        return ShelfBookmark(data: bookmark).resolveWithoutMounting()
    }

    /// What a double-click opens: the file or the link. Text tiles have nothing to open.
    var openableURL: URL? {
        switch kind {
        case .file: fileURL
        case .link(let url): url
        case .text: nil
        }
    }

    var displayName: String {
        switch kind {
        case .file:
            if let cachedDisplayName, !cachedDisplayName.isEmpty { return cachedDisplayName }
            return fileURL?.lastPathComponent ?? ""
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url):
            var text = url.absoluteString
            for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
            }
            return text
        }
    }

    /// Two drops of the same thing produce one tile: files compare by standardised path,
    /// links by URL, text by content.
    var identityKey: String {
        switch kind {
        case .file(let bookmark):
            if let url = fileURL {
                return "file:" + url.standardizedFileURL.path
            }
            return "file-bookmark:" + bookmark.base64EncodedString()
        case .link(let url):
            return "link:" + url.absoluteString
        case .text(let string):
            return "text:" + string
        }
    }
}
