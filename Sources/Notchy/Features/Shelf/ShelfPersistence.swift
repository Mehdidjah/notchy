import Foundation

/// The shelf on disk: one pretty-printed JSON array in
/// `Application Support/Notchy/Shelf/items.json`.
struct ShelfPersistence: Sendable {
    let fileURL: URL

    static let directoryName = "Shelf"
    static let fileName = "items.json"

    /// The shelf folder under the app's Application Support directory, created on demand.
    static func shelfDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try AppPaths.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func production() throws -> ShelfPersistence {
        ShelfPersistence(directory: try shelfDirectory())
    }

    init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Loads what was saved. A damaged entry is skipped rather than taking the whole shelf
    /// down with it.
    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = Self.makeDecoder()
        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }
        guard let rawItems = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return rawItems.compactMap { raw in
            // Only objects can be items; a stray scalar would make JSONSerialization throw.
            guard let object = raw as? [String: Any],
                  let itemData = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? decoder.decode(ShelfItem.self, from: itemData)
        }
    }

    func save(_ items: [ShelfItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
