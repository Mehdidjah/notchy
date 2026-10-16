import Foundation
import SwiftData

@Model
final class ClipRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var lastCopiedAt: Date
    var lastPastedAt: Date?
    var originalSourceDate: Date?
    var contentTypeRaw: String
    var plainText: String?
    var searchableText: String
    var richTextPayloadPath: String?
    var htmlPayloadPath: String?
    var imagePayloadPath: String?
    var thumbnailPath: String?
    var videoPath: String?
    var originalFileURLsData: Data
    var copiedFilePathsData: Data
    var urlValue: String?
    var urlTitle: String?
    var ocrText: String?
    var detectedLanguage: String?
    var detectedColorsData: Data
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
    var categoryIdentifiersData: Data
    var collectionIdentifier: UUID?
    var boardColumnIdentifier: UUID?
    var note: String?
    var inlineShortcut: String?
    var reminderIdentifier: UUID?
    var customOrder: Double
    var isLocalOnly: Bool
    var cloudSyncStateRaw: String
    var cardStyleRaw: String

    init(clip: Clip) {
        id = clip.id
        createdAt = clip.createdAt
        updatedAt = clip.updatedAt
        lastCopiedAt = clip.lastCopiedAt
        lastPastedAt = clip.lastPastedAt
        originalSourceDate = clip.originalSourceDate
        contentTypeRaw = clip.contentType.rawValue
        plainText = clip.plainText
        searchableText = clip.searchableText
        richTextPayloadPath = clip.richTextPayloadPath
        htmlPayloadPath = clip.htmlPayloadPath
        imagePayloadPath = clip.imagePayloadPath
        thumbnailPath = clip.thumbnailPath
        videoPath = clip.videoPath
        originalFileURLsData = Self.encode(clip.originalFileURLs)
        copiedFilePathsData = Self.encode(clip.copiedFilePaths)
        urlValue = clip.urlValue?.absoluteString
        urlTitle = clip.urlTitle
        ocrText = clip.ocrText
        detectedLanguage = clip.detectedLanguage
        detectedColorsData = Self.encode(clip.detectedColors)
        detectedCodeLanguage = clip.detectedCodeLanguage
        sourceApplicationBundleIdentifier = clip.sourceApplicationBundleIdentifier
        sourceApplicationName = clip.sourceApplicationName
        sourceApplicationIconReference = clip.sourceApplicationIconReference
        byteSize = clip.byteSize
        contentHash = clip.contentHash
        copyCount = clip.copyCount
        pasteCount = clip.pasteCount
        isFavorite = clip.isFavorite
        isPinned = clip.isPinned
        isSensitive = clip.isSensitive
        isManuallySaved = clip.isManuallySaved
        categoryIdentifiersData = Self.encode(clip.categoryIdentifiers)
        collectionIdentifier = clip.collectionIdentifier
        boardColumnIdentifier = clip.boardColumnIdentifier
        note = clip.note
        inlineShortcut = clip.inlineShortcut
        reminderIdentifier = clip.reminderIdentifier
        customOrder = clip.customOrder
        isLocalOnly = clip.isLocalOnly
        cloudSyncStateRaw = clip.cloudSyncState.rawValue
        cardStyleRaw = clip.cardStyle.rawValue
    }

    func update(from clip: Clip) {
        updatedAt = clip.updatedAt
        lastCopiedAt = clip.lastCopiedAt
        lastPastedAt = clip.lastPastedAt
        plainText = clip.plainText
        searchableText = clip.searchableText
        urlTitle = clip.urlTitle
        ocrText = clip.ocrText
        detectedLanguage = clip.detectedLanguage
        detectedColorsData = Self.encode(clip.detectedColors)
        detectedCodeLanguage = clip.detectedCodeLanguage
        copyCount = clip.copyCount
        pasteCount = clip.pasteCount
        isFavorite = clip.isFavorite
        isPinned = clip.isPinned
        isSensitive = clip.isSensitive
        isManuallySaved = clip.isManuallySaved
        categoryIdentifiersData = Self.encode(clip.categoryIdentifiers)
        collectionIdentifier = clip.collectionIdentifier
        boardColumnIdentifier = clip.boardColumnIdentifier
        note = clip.note
        inlineShortcut = clip.inlineShortcut
        reminderIdentifier = clip.reminderIdentifier
        customOrder = clip.customOrder
        isLocalOnly = clip.isLocalOnly
        cloudSyncStateRaw = clip.cloudSyncState.rawValue
        cardStyleRaw = clip.cardStyle.rawValue
    }

    func value() -> Clip {
        Clip(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastCopiedAt: lastCopiedAt,
            lastPastedAt: lastPastedAt,
            originalSourceDate: originalSourceDate,
            contentType: ClipType(rawValue: contentTypeRaw) ?? .generic,
            plainText: plainText,
            searchableText: searchableText,
            richTextPayloadPath: richTextPayloadPath,
            htmlPayloadPath: htmlPayloadPath,
            imagePayloadPath: imagePayloadPath,
            thumbnailPath: thumbnailPath,
            videoPath: videoPath,
            originalFileURLs: Self.decode([URL].self, from: originalFileURLsData) ?? [],
            copiedFilePaths: Self.decode([String].self, from: copiedFilePathsData) ?? [],
            urlValue: urlValue.flatMap(URL.init(string:)),
            urlTitle: urlTitle,
            ocrText: ocrText,
            detectedLanguage: detectedLanguage,
            detectedColors: Self.decode([String].self, from: detectedColorsData) ?? [],
            detectedCodeLanguage: detectedCodeLanguage,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            sourceApplicationName: sourceApplicationName,
            sourceApplicationIconReference: sourceApplicationIconReference,
            byteSize: byteSize,
            contentHash: contentHash,
            copyCount: copyCount,
            pasteCount: pasteCount,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            isManuallySaved: isManuallySaved,
            categoryIdentifiers: Self.decode([String].self, from: categoryIdentifiersData) ?? [],
            collectionIdentifier: collectionIdentifier,
            boardColumnIdentifier: boardColumnIdentifier,
            note: note,
            inlineShortcut: inlineShortcut,
            reminderIdentifier: reminderIdentifier,
            customOrder: customOrder,
            isLocalOnly: isLocalOnly,
            cloudSyncState: CloudSyncState(rawValue: cloudSyncStateRaw) ?? .local,
            cardStyle: ClipboardCardStyle(rawValue: cardStyleRaw) ?? .dark
        )
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
