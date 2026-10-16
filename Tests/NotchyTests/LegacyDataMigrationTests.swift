import Foundation
import Testing
@testable import Notchy

struct LegacyDataMigrationTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func movesTheOldSupportFolderOnce() throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("NotchIsland")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Payloads"), withIntermediateDirectories: true)
        try Data("db".utf8).write(to: legacy.appendingPathComponent("Clipboard.store"))
        try Data("wal".utf8).write(to: legacy.appendingPathComponent("Clipboard.store-wal"))

        let first = LegacyDataMigration.run(bundleIdentifier: nil, applicationSupport: base)
        #expect(first.movedSupportFolder)
        let current = base.appendingPathComponent(AppPaths.appFolderName)
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("Clipboard.store-wal").path))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("Payloads").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))

        let second = LegacyDataMigration.run(bundleIdentifier: nil, applicationSupport: base)
        #expect(!second.movedSupportFolder)
    }

    @Test func neverOverwritesAnExistingFolder() throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("NotchIsland")
        let current = base.appendingPathComponent(AppPaths.appFolderName)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: current.appendingPathComponent("Clipboard.store"))

        let result = LegacyDataMigration.run(bundleIdentifier: nil, applicationSupport: base)
        #expect(!result.movedSupportFolder)
        #expect(try Data(contentsOf: current.appendingPathComponent("Clipboard.store")) == Data("new".utf8))
    }

    @Test func copiesSettingsOnlyIntoAnEmptyDomain() throws {
        let defaults = UserDefaults.standard
        let legacyDomain = "LegacyDataMigrationTests.legacy.\(UUID().uuidString)"
        let domain = "LegacyDataMigrationTests.current.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.setPersistentDomain(["notch.showShadow": false, "notch.openNotchWidth": 700], forName: legacyDomain)

        #expect(LegacyDataMigration.copySettings(from: legacyDomain, to: domain, defaults: defaults))
        #expect(defaults.persistentDomain(forName: domain)?["notch.showShadow"] as? Bool == false)

        defaults.setPersistentDomain(["notch.showShadow": true], forName: domain)
        #expect(!LegacyDataMigration.copySettings(from: legacyDomain, to: domain, defaults: defaults))
        #expect(defaults.persistentDomain(forName: domain)?["notch.showShadow"] as? Bool == true)
    }
}
