import CryptoKit
import Foundation
import os
import Testing
@testable import Notchy

// MARK: - Doubles

private struct KeyProviderFailure: Error, LocalizedError {
    var errorDescription: String? { "The keychain is locked." }
}

/// Keeps the key in memory. Can be told to fail, to stand in for a locked keychain.
private final class MemoryKeyProvider: FaceCheckKeyProvider {
    private struct State: Sendable {
        var key: SymmetricKey?
        var failing = false
        var created = 0
        var deleted = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(key: SymmetricKey? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(key: key))
    }

    var key: SymmetricKey? { state.withLock { $0.key } }
    var createdCount: Int { state.withLock { $0.created } }
    var deletedCount: Int { state.withLock { $0.deleted } }

    func setFailing(_ failing: Bool) {
        state.withLock { $0.failing = failing }
    }

    func existingKey() throws -> SymmetricKey? {
        try state.withLock { state in
            if state.failing { throw KeyProviderFailure() }
            return state.key
        }
    }

    func createKey() throws -> SymmetricKey {
        try state.withLock { state in
            if state.failing { throw KeyProviderFailure() }
            let key = SymmetricKey(size: .bits256)
            state.key = key
            state.created += 1
            return key
        }
    }

    func deleteKey() throws {
        try state.withLock { state in
            if state.failing { throw KeyProviderFailure() }
            state.key = nil
            state.deleted += 1
        }
    }
}

// MARK: - Helpers

private func makeIdentity(_ name: String, model: String = "dlib-resnet-v1") -> FaceIdentity {
    let samples = (0..<3).map { index in
        FaceSample(
            descriptor: (0..<FaceDescriptor.dimension).map { Float($0 + index) * 0.001 - 0.05 },
            modelIdentifier: model,
            yaw: Double(index) * 7.5,
            pitch: -3.25,
            quality: 0.71,
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 0.75)
        )
    }
    return FaceIdentity(name: name, samples: samples)
}

private func sealed(_ json: String, key: SymmetricKey) throws -> Data {
    try #require(try AES.GCM.seal(
        Data(json.utf8),
        using: key,
        authenticating: FaceEnrollmentStore.associatedData
    ).combined)
}

// MARK: - Tests

/// A class so each test gets its own temporary folder, removed again when the test finishes.
final class FaceCheckEnrollmentStoreTests {
    private let directory: URL
    /// Where the store keeps its file inside this test's folder (the folder itself is created
    /// by the store's first save).
    private let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaceCheckStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = FaceEnrollmentStore.fileURL(inAppSupportDirectory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test
    func aMissingFileIsAnEmptyStore() async throws {
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
        #expect(await store.load() == .ready([]))
        #expect(try await store.identities().isEmpty)
    }

    @Test
    func identitiesSurviveASaveAndAFreshLoad() async throws {
        let keys = MemoryKeyProvider()
        let identities = [makeIdentity("Alice"), makeIdentity("Bob")]

        let writer = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        try await writer.replaceAll(with: identities)
        #expect(keys.createdCount == 1)

        let reader = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        #expect(await reader.load() == .ready(identities))
        #expect(try await reader.identities() == identities)
        // A second save reuses the key rather than making another.
        try await reader.replaceAll(with: [identities[0]])
        #expect(keys.createdCount == 1)
    }

    @Test
    func theFileIsSealedAndPrivate() async throws {
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
        try await store.replaceAll(with: [makeIdentity("Alice Example")])

        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("Alice Example".utf8)) == nil)
        #expect(bytes.range(of: Data("descriptor".utf8)) == nil)

        // Replace it once more so the check covers a save over an existing file too.
        try await store.replaceAll(with: [makeIdentity("Alice Example"), makeIdentity("Bob")])
        let folder = url.deletingLastPathComponent()
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        // The temporary file was renamed into place, so nothing else is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [FaceEnrollmentStore.fileName])
    }

    @Test
    func aFailedSaveKeepsThePreviousFileAndLeavesNothingBehind() async throws {
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
        let alice = makeIdentity("Alice")
        try await store.replaceAll(with: [alice])
        let original = try Data(contentsOf: url)

        // A folder Notchy can no longer write to: the save must fail without touching the file.
        let folder = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        await #expect(throws: FaceEnrollmentStoreError.self) {
            try await store.upsert(makeIdentity("Bob"))
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [FaceEnrollmentStore.fileName])
        #expect(await store.state == .ready([alice]))
    }

    @Test
    func aFileTheKeyCannotOpenIsNeverOverwritten() async throws {
        try await FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
            .replaceAll(with: [makeIdentity("Alice")])
        let original = try Data(contentsOf: url)

        let otherKey = MemoryKeyProvider(key: SymmetricKey(size: .bits256))
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: otherKey)
        #expect(await store.load() == .unreadable(.cannotDecrypt))
        #expect(FaceEnrollmentUnreadableReason.cannotDecrypt.requiresReenrolment)

        await #expect(throws: FaceEnrollmentStoreError.unreadable(.cannotDecrypt)) {
            try await store.replaceAll(with: [])
        }
        await #expect(throws: FaceEnrollmentStoreError.unreadable(.cannotDecrypt)) {
            try await store.upsert(makeIdentity("Mallory"))
        }
        await #expect(throws: FaceEnrollmentStoreError.unreadable(.cannotDecrypt)) {
            try await store.identities()
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(otherKey.createdCount == 0)
    }

    @Test
    func aLostKeyMeansReenrolment() async throws {
        let keys = MemoryKeyProvider()
        try await FaceEnrollmentStore(fileURL: url, keyProvider: keys).replaceAll(with: [makeIdentity("Alice")])
        let original = try Data(contentsOf: url)

        // A keychain reset after a rebuild: the file is still there, its key is not.
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
        #expect(await store.load() == .unreadable(.keyMissing))
        #expect(FaceEnrollmentUnreadableReason.keyMissing.requiresReenrolment)
        await #expect(throws: FaceEnrollmentStoreError.unreadable(.keyMissing)) {
            try await store.replaceAll(with: [makeIdentity("Bob")])
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func aKeyThatIsOnlyUnavailableCanBeRetried() async throws {
        let keys = MemoryKeyProvider()
        let identities = [makeIdentity("Alice")]
        try await FaceEnrollmentStore(fileURL: url, keyProvider: keys).replaceAll(with: identities)

        keys.setFailing(true)
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        let state = await store.load()
        guard case .unreadable(.keyUnavailable(let message)) = state else {
            Issue.record("Expected an unavailable key, got \(state)")
            return
        }
        #expect(message == "The keychain is locked.")
        #expect(!FaceEnrollmentUnreadableReason.keyUnavailable(message).requiresReenrolment)

        keys.setFailing(false)
        #expect(await store.load() == .ready(identities))
    }

    @Test
    func anUnreadableStoreReadsAgainBeforeEachUse() async throws {
        let keys = MemoryKeyProvider()
        let alice = makeIdentity("Alice")
        try await FaceEnrollmentStore(fileURL: url, keyProvider: keys).replaceAll(with: [alice])

        keys.setFailing(true)
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        await #expect(throws: FaceEnrollmentStoreError.unreadable(.keyUnavailable("The keychain is locked."))) {
            try await store.upsert(makeIdentity("Bob"))
        }

        // Once the keychain answers again the next call picks the file up, with no explicit
        // reload, and the edit lands on top of what was already stored.
        keys.setFailing(false)
        let bob = makeIdentity("Bob")
        try await store.upsert(bob)
        #expect(try await store.identities() == [alice, bob])
        #expect(keys.createdCount == 1)
    }

    @Test
    func aDamagedFileIsReportedNotReplaced() async throws {
        let keys = MemoryKeyProvider()
        try await FaceEnrollmentStore(fileURL: url, keyProvider: keys).replaceAll(with: [makeIdentity("Alice")])
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)

        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        #expect(await store.load() == .unreadable(.cannotDecrypt))
        #expect(try Data(contentsOf: url) == bytes)

        try Data("not sealed".utf8).write(to: url)
        #expect(await store.load() == .unreadable(.cannotDecrypt))
    }

    @Test
    func contentsFaceCheckDoesNotUnderstandAreRefused() async throws {
        let key = SymmetricKey(size: .bits256)
        let keys = MemoryKeyProvider(key: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)

        try sealed(#"{"version": 99, "identities": "from the future"}"#, key: key).write(to: url)
        #expect(await store.load() == .unreadable(.unsupportedVersion(99)))
        #expect(!FaceEnrollmentUnreadableReason.unsupportedVersion(99).requiresReenrolment)

        try sealed(#"{"version": 1, "identities": 42}"#, key: key).write(to: url)
        #expect(await store.load() == .unreadable(.damaged))

        // Sealed with the right key but for some other purpose.
        let foreign = try #require(try AES.GCM.seal(Data(#"{"version":1,"identities":[]}"#.utf8), using: key).combined)
        try foreign.write(to: url)
        #expect(await store.load() == .unreadable(.cannotDecrypt))
    }

    @Test
    func deletingEverythingClearsAnUnreadableStore() async throws {
        try await FaceEnrollmentStore(fileURL: url, keyProvider: MemoryKeyProvider())
            .replaceAll(with: [makeIdentity("Alice")])

        let keys = MemoryKeyProvider(key: SymmetricKey(size: .bits256))
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        #expect(await store.load() == .unreadable(.cannotDecrypt))

        try await store.deleteAll()
        #expect(await store.state == .ready([]))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(keys.key == nil)
        #expect(keys.deletedCount == 1)

        // Enrolling again starts with a fresh key.
        let bob = makeIdentity("Bob")
        try await store.upsert(bob)
        #expect(keys.createdCount == 1)
        #expect(await FaceEnrollmentStore(fileURL: url, keyProvider: keys).load() == .ready([bob]))
    }

    @Test
    func deleteAllWithNothingStoredSucceeds() async throws {
        let keys = MemoryKeyProvider()
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        try await store.deleteAll()
        #expect(await store.state == .ready([]))
    }

    @Test
    func aKeyThatWillNotGoAwayIsReportedAfterTheFacesAreGone() async throws {
        let keys = MemoryKeyProvider()
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        try await store.replaceAll(with: [makeIdentity("Alice")])

        keys.setFailing(true)
        await #expect(throws: FaceEnrollmentStoreError.deleteFailed("The keychain is locked.")) {
            try await store.deleteAll()
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await store.state == .ready([]))
    }

    @Test
    func upsertAndRemoveEditOneIdentity() async throws {
        let keys = MemoryKeyProvider()
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        var alice = makeIdentity("Alice")
        let bob = makeIdentity("Bob")
        try await store.upsert(alice)
        try await store.upsert(bob)

        alice.isEnabled = false
        alice.name = "Alice R."
        try await store.upsert(alice)
        #expect(try await store.identities() == [alice, bob])

        try await store.removeIdentity(id: bob.id)
        try await store.removeIdentity(id: UUID())
        #expect(await FaceEnrollmentStore(fileURL: url, keyProvider: keys).load() == .ready([alice]))
    }

    @Test
    func aSaveFailsCleanlyWhenNoKeyCanBeMade() async throws {
        let keys = MemoryKeyProvider()
        keys.setFailing(true)
        let store = FaceEnrollmentStore(fileURL: url, keyProvider: keys)
        await #expect(throws: FaceEnrollmentStoreError.keyUnavailable("The keychain is locked.")) {
            try await store.replaceAll(with: [makeIdentity("Alice")])
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await store.state == .ready([]))
    }

    @Test
    func theFileSitsInItsOwnFolderInsideAppSupport() {
        // Checked on a made-up folder so the test never creates Notchy's real one.
        let appSupport = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
            .appendingPathComponent(AppPaths.appFolderName, isDirectory: true)
        let file = FaceEnrollmentStore.fileURL(inAppSupportDirectory: appSupport)
        #expect(file.path == "/Users/someone/Library/Application Support/Notchy/FaceCheck/identities.sealed")
    }
}
