import AppKit
import Foundation
import UniformTypeIdentifiers

/// Providers handed over by a drop. `NSItemProvider` is documented as thread-safe but is not
/// marked `Sendable`; this box carries a drop from the main actor to the importer.
struct ShelfDroppedProviders: @unchecked Sendable {
    let providers: [NSItemProvider]

    init(_ providers: [NSItemProvider]) {
        self.providers = providers
    }
}

/// Turns what another app dropped into shelf items. Files stay where they are and are
/// bookmarked; images, raw data and text that have no file behind them are written to the
/// shelf's own folder first so they can be dragged out again as files later.
struct ShelfDropImporter: Sendable {
    let temporaryFiles: ShelfTemporaryFileStore

    /// The types the shelf's drop zones accept, in the order a provider is probed.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    func items(from dropped: ShelfDroppedProviders) async -> [ShelfItem] {
        var results: [ShelfItem] = []
        for provider in dropped.providers {
            if let item = await item(from: provider) {
                results.append(item)
            }
        }
        return results
    }

    /// Bookmarks existing files; anything missing is skipped.
    func items(from fileURLs: [URL]) -> [ShelfItem] {
        fileURLs.compactMap { url in
            guard url.isFileURL else { return nil }
            return try? ShelfItem.file(at: url)
        }
    }

    private func item(from provider: NSItemProvider) async -> ShelfItem? {
        if let url = await Self.loadURL(from: provider, type: .fileURL), url.isFileURL {
            return try? ShelfItem.file(at: url)
        }
        if let image = await Self.loadImage(from: provider) {
            let name = provider.suggestedName.map { Self.ensureExtension($0, image.type) }
                ?? "Image." + (image.type.preferredFilenameExtension ?? "png")
            guard let url = try? temporaryFiles.write(data: image.data, preferredName: name) else { return nil }
            return try? ShelfItem.file(at: url, isTemporary: true)
        }
        if let url = await Self.loadURL(from: provider, type: .url) {
            if url.isFileURL {
                return try? ShelfItem.file(at: url)
            }
            return .link(url)
        }
        if let text = await Self.loadText(from: provider),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    // MARK: Provider probes

    private static func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        let identifier = provider.registeredTypeIdentifiers
            .first { UTType($0)?.conforms(to: type) == true || $0 == type.identifier }
        guard let identifier, let data = await loadData(from: provider, identifier: identifier) else { return nil }
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private struct LoadedImage: Sendable {
        let data: Data
        let type: UTType
    }

    /// Picks the most specific image representation on offer. An abstract `public.image`
    /// payload is re-encoded as PNG so the file on disk has a real format.
    private static func loadImage(from provider: NSItemProvider) async -> LoadedImage? {
        let candidates = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .filter { $0.conforms(to: .image) }
        guard !candidates.isEmpty else { return nil }
        let preferred = candidates.first { $0 != .image && $0.preferredFilenameExtension != nil } ?? candidates[0]
        guard let data = await loadData(from: provider, identifier: preferred.identifier) else { return nil }
        if preferred != .image, preferred.preferredFilenameExtension != nil {
            return LoadedImage(data: data, type: preferred)
        }
        guard let png = pngData(from: data) else { return nil }
        return LoadedImage(data: png, type: .png)
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        let identifier = identifiers.first { $0 == UTType.utf8PlainText.identifier }
            ?? identifiers.first { UTType($0)?.conforms(to: .plainText) == true }
        guard let identifier, let data = await loadData(from: provider, identifier: identifier) else { return nil }
        if identifier == UTType.utf16ExternalPlainText.identifier || identifier == UTType.utf16PlainText.identifier {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    private static func loadData(from provider: NSItemProvider, identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func pngData(from data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func ensureExtension(_ name: String, _ type: UTType) -> String {
        guard let preferred = type.preferredFilenameExtension else { return name }
        let current = (name as NSString).pathExtension
        if let currentType = UTType(filenameExtension: current), currentType.conforms(to: .image) {
            return name
        }
        return name + "." + preferred
    }
}
