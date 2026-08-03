import Foundation

enum AppPaths {
    static let appFolderName = "NotchIsland"

    static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(appFolderName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func metadataStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Clipboard.store", isDirectory: false)
    }

    static func payloadDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Payloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
