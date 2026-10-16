import AppKit
import QuickLookThumbnailing

/// Carries an image across an isolation boundary. The image is built once and only read
/// afterwards, which is what makes the hop safe.
struct ShelfImageBox: @unchecked Sendable {
    let image: NSImage
}

/// Quick Look thumbnails for file tiles, with the Finder icon as the fallback and a cache so
/// a tile that scrolls back into view is drawn at once.
@MainActor
final class ShelfThumbnailCache {
    static let shared = ShelfThumbnailCache()
    /// Atoll draws file tiles at 56 x 56 points.
    static let tileSize = CGSize(width: 56, height: 56)

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func cachedThumbnail(for url: URL) -> NSImage? {
        cache[Self.key(url, Self.tileSize)]
    }

    func thumbnail(for url: URL, size: CGSize = tileSize) async -> NSImage? {
        let key = Self.key(url, size)
        if let cached = cache[key] { return cached }
        if let pending = inFlight[key] { return await pending.value }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let task = Task<NSImage?, Never> {
            let generated = await Self.generate(url: url, size: size, scale: scale)
                ?? Self.workspaceIcon(for: url)
            return generated?.image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache[key] = image }
        return image
    }

    func invalidate(_ url: URL) {
        let prefix = url.standardizedFileURL.path + "|"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    /// A white card with a symbol on it: the tile for text and links, which have no file to
    /// thumbnail.
    static func symbolCard(systemName: String) -> NSImage {
        let size = NSSize(width: 64, height: 80)
        return NSImage(size: size, flipped: false) { rect in
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
            NSColor.white.setFill()
            card.fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
            if let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let symbolSize = symbol.size
                let origin = NSPoint(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2)
                symbol.draw(in: NSRect(origin: origin, size: symbolSize))
            }
            return true
        }
    }

    private static func key(_ url: URL, _ size: CGSize) -> String {
        "\(url.standardizedFileURL.path)|\(Int(size.width))x\(Int(size.height))"
    }

    private nonisolated static func generate(url: URL, size: CGSize, scale: CGFloat) async -> ShelfImageBox? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        request.iconMode = true
        return await withCheckedContinuation { (continuation: CheckedContinuation<ShelfImageBox?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let cgImage = representation?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let pointSize = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                continuation.resume(returning: ShelfImageBox(image: NSImage(cgImage: cgImage, size: pointSize)))
            }
        }
    }

    private nonisolated static func workspaceIcon(for url: URL) -> ShelfImageBox? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ShelfImageBox(image: NSWorkspace.shared.icon(forFile: url.path))
    }
}
