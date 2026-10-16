import Foundation

/// Files the shelf writes for content that arrived without one (dropped text, images, raw
/// data). Each lands in its own folder under `Application Support/NotchIsland/Shelf/Drops` so
/// names never collide, and is deleted again when its tile leaves the shelf.
struct ShelfTemporaryFileStore: Sendable {
    let rootDirectory: URL

    static let directoryName = "Drops"
    static let fallbackName = "Dropped item"

    static func production() throws -> ShelfTemporaryFileStore {
        let root = try ShelfPersistence.shelfDirectory()
            .appendingPathComponent(directoryName, isDirectory: true)
        return ShelfTemporaryFileStore(rootDirectory: root)
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func write(data: Data, preferredName: String) throws -> URL {
        let folder = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Self.sanitizedFileName(preferredName), isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Text becomes a `.txt` named after its first line, so the tile reads like the note.
    func writeText(_ text: String) throws -> URL {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? "Text"
        let stem = String(firstLine.prefix(40))
        return try write(data: Data(text.utf8), preferredName: stem + ".txt")
    }

    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootDirectory.path + "/")
    }

    /// Deletes a file this store wrote, plus its now-empty folder. Paths outside the store
    /// are left alone so a stale flag can never delete a user's file.
    func remove(_ url: URL) {
        guard contains(url) else { return }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        let folder = url.deletingLastPathComponent()
        guard folder.standardizedFileURL != rootDirectory,
              let contents = try? fileManager.contentsOfDirectory(atPath: folder.path),
              contents.isEmpty else { return }
        try? fileManager.removeItem(at: folder)
    }

    static func sanitizedFileName(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { cleaned = fallbackName }
        if cleaned.hasPrefix(".") { cleaned = fallbackName + cleaned }
        return String(cleaned.prefix(200))
    }
}
