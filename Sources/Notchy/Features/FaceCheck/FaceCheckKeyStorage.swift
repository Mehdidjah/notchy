import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Holds the key that seals the enrolment store, without the keychain.
///
/// Notchy is not signed with a developer team, so the data-protection keychain refuses it, and
/// file-keychain items are tied to the exact build that made them: every rebuild would lose its
/// own key. A Secure Enclave key avoids both. The enclave keeps a private key that never leaves
/// this Mac; its opaque handle is saved next to the store together with a public key made once
/// with it, and the store key is derived from the agreement between the two. Nothing secret is
/// written to disk, a rebuilt Notchy derives the same key, and a copy of the files is useless on
/// any other Mac. Macs without a Secure Enclave fall back to a random key in an owner-only file.
struct FaceCheckKeyStorage: FaceCheckKeyProvider {
    enum Failure: LocalizedError {
        case incomplete
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .incomplete: "Part of Face Check's key is missing."
            case .unreadable(let detail): "Face Check's key could not be read (\(detail))."
            }
        }
    }

    static let enclaveKeyFile = "store-key.sep"
    static let peerKeyFile = "store-key.peer"
    static let plainKeyFile = "store-key.bin"
    private static let derivationInfo = Data("Notchy.FaceCheck.store-key.v1".utf8)

    let directory: URL
    var usesSecureEnclave: Bool = SecureEnclave.isAvailable

    /// The key folder next to the enrolment store.
    static func standard(fileManager: FileManager = .default) throws -> FaceCheckKeyStorage {
        let directory = try FaceEnrollmentStore.defaultFileURL(fileManager: fileManager).deletingLastPathComponent()
        return FaceCheckKeyStorage(directory: directory)
    }

    func existingKey() throws -> SymmetricKey? {
        let enclave = directory.appendingPathComponent(Self.enclaveKeyFile)
        let peer = directory.appendingPathComponent(Self.peerKeyFile)
        let plain = directory.appendingPathComponent(Self.plainKeyFile)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: enclave.path) || fileManager.fileExists(atPath: peer.path) {
            guard fileManager.fileExists(atPath: enclave.path), fileManager.fileExists(atPath: peer.path) else {
                throw Failure.incomplete
            }
            do {
                let handle = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                    dataRepresentation: try Data(contentsOf: enclave),
                    authenticationContext: Self.silentContext()
                )
                let record = try FaceCheckKeyPeer(data: try Data(contentsOf: peer))
                return try Self.derive(enclaveKey: handle, peer: record)
            } catch let error as Failure {
                throw error
            } catch {
                throw Failure.unreadable(error.localizedDescription)
            }
        }
        if fileManager.fileExists(atPath: plain.path) {
            let bytes = try Data(contentsOf: plain)
            guard bytes.count == 32 else { throw Failure.unreadable("wrong length") }
            return SymmetricKey(data: bytes)
        }
        return nil
    }

    func createKey() throws -> SymmetricKey {
        try prepareDirectory()
        if usesSecureEnclave {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], &error
            ) else {
                throw Failure.unreadable(error?.takeRetainedValue().localizedDescription ?? "access control")
            }
            let handle = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                accessControl: access,
                authenticationContext: Self.silentContext()
            )
            // The peer's private half is thrown away at once: only its public key and the salt
            // are needed to derive the same key again with the enclave key.
            let peer = FaceCheckKeyPeer(
                publicKey: P256.KeyAgreement.PrivateKey().publicKey.x963Representation,
                salt: Self.randomBytes(32)
            )
            let key = try Self.derive(enclaveKey: handle, peer: peer)
            try writeOwnerOnly(handle.dataRepresentation, to: Self.enclaveKeyFile)
            try writeOwnerOnly(peer.data, to: Self.peerKeyFile)
            return key
        }
        let bytes = Self.randomBytes(32)
        try writeOwnerOnly(bytes, to: Self.plainKeyFile)
        return SymmetricKey(data: bytes)
    }

    func deleteKey() throws {
        for name in [Self.enclaveKeyFile, Self.peerKeyFile, Self.plainKeyFile] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Helpers

    static func derive(enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey, peer: FaceCheckKeyPeer) throws -> SymmetricKey {
        let peerKey = try P256.KeyAgreement.PublicKey(x963Representation: peer.publicKey)
        let shared = try enclaveKey.sharedSecretFromKeyAgreement(with: peerKey)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: peer.salt,
            sharedInfo: derivationInfo,
            outputByteCount: 32
        )
    }

    /// The enclave key never asks for Touch ID; this makes sure no prompt can ever appear.
    private static func silentContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private func prepareDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// Owner-only and left out of backups: the files are useless on any other Mac.
    private func writeOwnerOnly(_ data: Data, to name: String) throws {
        var url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// The public half and salt saved beside the enclave key: 65-byte X9.63 public key + 32-byte salt.
struct FaceCheckKeyPeer: Equatable, Sendable {
    var publicKey: Data
    var salt: Data

    init(publicKey: Data, salt: Data) {
        self.publicKey = publicKey
        self.salt = salt
    }

    init(data: Data) throws {
        guard data.count == 65 + 32 else { throw FaceCheckKeyStorage.Failure.unreadable("peer record length") }
        publicKey = data.prefix(65)
        salt = data.suffix(32)
    }

    var data: Data { publicKey + salt }
}
