import Foundation

/// The app used to be called NotchIsland. On the first launch as Notchy, carry its data over
/// so nothing is lost: the Application Support folder (clipboard store, payloads, shelf) is
/// moved, and the settings are copied from the old defaults domain. Each step runs only while
/// Notchy has nothing of its own yet, so it never overwrites newer data.
enum LegacyDataMigration {
    static let legacyFolderName = "NotchIsland"
    static let legacyBundleIdentifier = "com.local.NotchIsland"

    struct Result: Equatable {
        var movedSupportFolder = false
        var copiedSettings = false
    }

    @discardableResult
    static func run(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationSupport: URL? = nil,
        legacyFolderName: String = legacyFolderName,
        legacyBundleIdentifier: String = legacyBundleIdentifier
    ) -> Result {
        var result = Result()
        if let base = applicationSupport ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            result.movedSupportFolder = moveSupportFolder(
                from: base.appendingPathComponent(legacyFolderName, isDirectory: true),
                to: base.appendingPathComponent(AppPaths.appFolderName, isDirectory: true),
                fileManager: fileManager
            )
        }
        if let bundleIdentifier, bundleIdentifier != legacyBundleIdentifier {
            result.copiedSettings = copySettings(from: legacyBundleIdentifier, to: bundleIdentifier, defaults: defaults)
        }
        return result
    }

    /// Moves the whole folder, so the store's write-ahead log travels with it.
    static func moveSupportFolder(from legacy: URL, to current: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: current.path) else {
            return false
        }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            return true
        } catch {
            return false
        }
    }

    static func copySettings(from legacyDomain: String, to domain: String, defaults: UserDefaults) -> Bool {
        let existing = defaults.persistentDomain(forName: domain) ?? [:]
        guard existing.isEmpty,
              let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty
        else { return false }
        defaults.setPersistentDomain(legacy, forName: domain)
        return true
    }
}
