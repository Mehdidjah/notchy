import Foundation

enum ClipType: String, CaseIterable, Codable, Hashable, Sendable {
    case plainText
    case multipleParagraphs
    case richText
    case html
    case url
    case email
    case phoneNumber
    case code
    case json
    case shellCommand
    case color
    case svg
    case image
    case screenshot
    case gif
    case video
    case pdf
    case file
    case folder
    case multipleFiles
    case clipGroup
    case generic

    var displayName: String {
        switch self {
        case .plainText: "Text"
        case .multipleParagraphs: "Paragraphs"
        case .richText: "Rich Text"
        case .html: "HTML"
        case .url: "Link"
        case .email: "Email"
        case .phoneNumber: "Phone"
        case .code: "Code"
        case .json: "JSON"
        case .shellCommand: "Shell"
        case .color: "Color"
        case .svg: "SVG"
        case .image: "Image"
        case .screenshot: "Screenshot"
        case .gif: "GIF"
        case .video: "Video"
        case .pdf: "PDF"
        case .file: "File"
        case .folder: "Folder"
        case .multipleFiles: "Files"
        case .clipGroup: "Clip Group"
        case .generic: "Clipboard Data"
        }
    }

    var systemImage: String {
        switch self {
        case .plainText, .multipleParagraphs, .richText: "doc.text.fill"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .url: "link"
        case .email: "envelope.fill"
        case .phoneNumber: "phone.fill"
        case .code, .json, .shellCommand: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette.fill"
        case .svg, .image, .screenshot, .gif: "photo.fill"
        case .video: "film.fill"
        case .pdf: "doc.richtext.fill"
        case .file: "doc.fill"
        case .folder: "folder.fill"
        case .multipleFiles: "square.stack.3d.up.fill"
        case .clipGroup: "square.stack.3d.forward.dottedline.fill"
        case .generic: "doc.on.clipboard.fill"
        }
    }
}

enum CloudSyncState: String, Codable, Hashable, Sendable {
    case local
    case pending
    case synced
    case conflict
    case failed
}

enum ClipboardItemKind: String, Codable, Hashable, Sendable {
    case text
    case link
    case color
    case code
    case image
    case file
    case group
    case generic
}

enum ClipboardCardStyle: String, Codable, Hashable, Sendable {
    case light
    case dark
    case blue
    case teal
}

/// The app's value-model boundary. Large binary representations live in Application Support and
/// are referenced here by relative path, keeping UI work and the SwiftData store lightweight.
struct Clip: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var lastCopiedAt: Date
    var lastPastedAt: Date?
    var originalSourceDate: Date?
    var contentType: ClipType
    var plainText: String?
    var searchableText: String
    var richTextPayloadPath: String?
    var htmlPayloadPath: String?
    var imagePayloadPath: String?
    var thumbnailPath: String?
    var videoPath: String?
    var originalFileURLs: [URL]
    var copiedFilePaths: [String]
    var urlValue: URL?
    var urlTitle: String?
    var ocrText: String?
    var detectedLanguage: String?
    var detectedColors: [String]
    var detectedCodeLanguage: String?
    var sourceApplicationBundleIdentifier: String?
    var sourceApplicationName: String?
    var sourceApplicationIconReference: String?
    var byteSize: Int64
    var contentHash: String
    var copyCount: Int
    var pasteCount: Int
    var isFavorite: Bool
    var isPinned: Bool
    var isSensitive: Bool
    var isManuallySaved: Bool
    var categoryIdentifiers: [String]
    var collectionIdentifier: UUID?
    var boardColumnIdentifier: UUID?
    var note: String?
    var inlineShortcut: String?
    var reminderIdentifier: UUID?
    var customOrder: Double
    var isLocalOnly: Bool
    var cloudSyncState: CloudSyncState
    var cardStyle: ClipboardCardStyle

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        lastPastedAt: Date? = nil,
        originalSourceDate: Date? = nil,
        contentType: ClipType,
        plainText: String? = nil,
        searchableText: String? = nil,
        richTextPayloadPath: String? = nil,
        htmlPayloadPath: String? = nil,
        imagePayloadPath: String? = nil,
        thumbnailPath: String? = nil,
        videoPath: String? = nil,
        originalFileURLs: [URL] = [],
        copiedFilePaths: [String] = [],
        urlValue: URL? = nil,
        urlTitle: String? = nil,
        ocrText: String? = nil,
        detectedLanguage: String? = nil,
        detectedColors: [String] = [],
        detectedCodeLanguage: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        sourceApplicationName: String? = nil,
        sourceApplicationIconReference: String? = nil,
        byteSize: Int64 = 0,
        contentHash: String,
        copyCount: Int = 1,
        pasteCount: Int = 0,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        isManuallySaved: Bool = false,
        categoryIdentifiers: [String] = [],
        collectionIdentifier: UUID? = nil,
        boardColumnIdentifier: UUID? = nil,
        note: String? = nil,
        inlineShortcut: String? = nil,
        reminderIdentifier: UUID? = nil,
        customOrder: Double = 0,
        isLocalOnly: Bool = true,
        cloudSyncState: CloudSyncState = .local,
        cardStyle: ClipboardCardStyle = .dark
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCopiedAt = lastCopiedAt
        self.lastPastedAt = lastPastedAt
        self.originalSourceDate = originalSourceDate
        self.contentType = contentType
        self.plainText = plainText
        self.searchableText = searchableText ?? plainText ?? urlValue?.absoluteString ?? ""
        self.richTextPayloadPath = richTextPayloadPath
        self.htmlPayloadPath = htmlPayloadPath
        self.imagePayloadPath = imagePayloadPath
        self.thumbnailPath = thumbnailPath
        self.videoPath = videoPath
        self.originalFileURLs = originalFileURLs
        self.copiedFilePaths = copiedFilePaths
        self.urlValue = urlValue
        self.urlTitle = urlTitle
        self.ocrText = ocrText
        self.detectedLanguage = detectedLanguage
        self.detectedColors = detectedColors
        self.detectedCodeLanguage = detectedCodeLanguage
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationIconReference = sourceApplicationIconReference
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.copyCount = copyCount
        self.pasteCount = pasteCount
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.isManuallySaved = isManuallySaved
        self.categoryIdentifiers = categoryIdentifiers
        self.collectionIdentifier = collectionIdentifier
        self.boardColumnIdentifier = boardColumnIdentifier
        self.note = note
        self.inlineShortcut = inlineShortcut
        self.reminderIdentifier = reminderIdentifier
        self.customOrder = customOrder
        self.isLocalOnly = isLocalOnly
        self.cloudSyncState = cloudSyncState
        self.cardStyle = cardStyle
    }

    /// Compatibility initializer for the first visual prototype. It remains available to tests
    /// and callers while production capture uses the complete initializer above.
    init(
        id: UUID = UUID(),
        title: String,
        value: String,
        detail: String,
        kind: ClipboardItemKind,
        style: ClipboardCardStyle,
        symbolName _: String,
        isPinned: Bool = false
    ) {
        let now = Date()
        let type: ClipType = switch kind {
        case .text: .plainText
        case .link: .url
        case .color: .color
        case .code: .code
        case .image: .image
        case .file: .file
        case .group: .clipGroup
        case .generic: .generic
        }
        self.init(
            id: id,
            createdAt: now,
            updatedAt: now,
            lastCopiedAt: now,
            contentType: type,
            plainText: value,
            searchableText: [title, value, detail].joined(separator: "\n"),
            urlValue: kind == .link ? URL(string: value) : nil,
            sourceApplicationName: detail.components(separatedBy: " · ").first,
            contentHash: value,
            isPinned: isPinned,
            cardStyle: style
        )
    }

    var title: String {
        if let urlTitle, !urlTitle.isEmpty { return urlTitle }
        if let plainText, !plainText.isEmpty { return plainText }
        if originalFileURLs.count == 1 { return originalFileURLs[0].lastPathComponent }
        if originalFileURLs.count > 1 { return "\(originalFileURLs.count) files" }
        return contentType.displayName
    }

    var value: String {
        plainText ?? urlValue?.absoluteString ?? originalFileURLs.map(\.path).joined(separator: "\n")
    }

    var detail: String {
        let app = sourceApplicationName ?? "Clipboard"
        return "\(app) · \(lastCopiedAt.relativeDescription)"
    }

    var kind: ClipboardItemKind {
        switch contentType {
        case .plainText, .multipleParagraphs, .richText, .html, .email, .phoneNumber: .text
        case .url: .link
        case .color: .color
        case .code, .json, .shellCommand: .code
        case .svg, .image, .screenshot, .gif, .video: .image
        case .pdf, .file, .folder, .multipleFiles: .file
        case .clipGroup: .group
        case .generic: .generic
        }
    }

    var style: ClipboardCardStyle { cardStyle }
    var symbolName: String { contentType.systemImage }
}

/// Source-compatible name retained from the initial prototype.
typealias ClipboardItem = Clip

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
