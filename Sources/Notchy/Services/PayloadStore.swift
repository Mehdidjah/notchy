import Foundation

actor PayloadStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func production() throws -> PayloadStore {
        try PayloadStore(directory: AppPaths.payloadDirectory())
    }

    func store(_ data: Data, clipID: UUID, fileExtension: String) throws -> String {
        let safeExtension = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let filename = safeExtension.isEmpty
            ? clipID.uuidString
            : "\(clipID.uuidString).\(safeExtension)"
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return filename
    }

    func data(at relativePath: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(relativePath, isDirectory: false))
    }

    func remove(relativePath: String?) throws {
        guard let relativePath else { return }
        let url = directory.appendingPathComponent(relativePath, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeOrphans(referencedPaths: Set<String>) throws -> Int {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for file in files where !referencedPaths.contains(file.lastPathComponent) {
            try fileManager.removeItem(at: file)
            removed += 1
        }
        return removed
    }
}
