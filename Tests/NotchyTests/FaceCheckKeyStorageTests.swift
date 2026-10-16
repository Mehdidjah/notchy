import CryptoKit
import Foundation
import Testing
@testable import Notchy

struct FaceCheckKeyStorageTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FaceCheckKeys-\(UUID().uuidString)")
    }

    private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    @Test(.enabled(if: SecureEnclave.isAvailable))
    func enclaveKeyDerivesTheSameKeyAfterReloading() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FaceCheckKeyStorage(directory: directory)
        #expect(try storage.existingKey() == nil)

        let created = try storage.createKey()
        let reloaded = try #require(try FaceCheckKeyStorage(directory: directory).existingKey())
        #expect(bytes(created) == bytes(reloaded))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(FaceCheckKeyStorage.plainKeyFile).path))

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(FaceCheckKeyStorage.peerKeyFile).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try storage.deleteKey()
        #expect(try storage.existingKey() == nil)
    }

    @Test(.enabled(if: SecureEnclave.isAvailable))
    func aHalfMissingEnclaveKeyIsAnErrorNotANewKey() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FaceCheckKeyStorage(directory: directory)
        _ = try storage.createKey()
        try FileManager.default.removeItem(at: directory.appendingPathComponent(FaceCheckKeyStorage.peerKeyFile))
        #expect(throws: FaceCheckKeyStorage.Failure.self) { try storage.existingKey() }
    }

    @Test func withoutTheEnclaveARandomKeyFileIsUsed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var storage = FaceCheckKeyStorage(directory: directory)
        storage.usesSecureEnclave = false
        let created = try storage.createKey()
        let reloaded = try #require(try storage.existingKey())
        #expect(bytes(created) == bytes(reloaded))
        #expect(bytes(created).count == 32)
    }

    @Test func peerRecordRoundTripsAndRejectsWrongLengths() throws {
        let peer = FaceCheckKeyPeer(publicKey: Data(repeating: 4, count: 65), salt: Data(repeating: 7, count: 32))
        #expect(try FaceCheckKeyPeer(data: peer.data) == peer)
        #expect(throws: FaceCheckKeyStorage.Failure.self) { try FaceCheckKeyPeer(data: Data(count: 10)) }
    }
}
