import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import OpenDirectory
import Security
import os

struct MacUnlockBinding: Codable, Equatable, Sendable {
    var identityID: UUID
    var enrollmentDigest: Data
    var accountUID: UInt32
}

@MainActor
protocol MacUnlockCredentialAccess: AnyObject {
    /// Metadata is untrusted after load; it becomes authenticated only while isArmed is true.
    var binding: MacUnlockBinding? { get }
    var isArmed: Bool { get }
    func load() throws
    func save(password: String, binding: MacUnlockBinding) async throws
    func arm() async throws
    /// The caller must promptly erase the returned buffer after its single intended use.
    func password(for binding: MacUnlockBinding) throws -> Data
    func disarm()
    func delete() throws
    func recordSuccessfulUnlock()
}

extension MacUnlockCredentialAccess { func recordSuccessfulUnlock() {} }

enum MacUnlockVaultError: Error, Equatable, LocalizedError {
    case secureEnclaveUnavailable, invalidPassword, passwordValidationFailed
    case authenticationFailed, cancelled, missingCredential, invalidRecord
    case wrongAccount, bindingMismatch, notArmed, recordChanged, persistenceFailed, unsafePermissions

    var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable: "This Mac cannot securely store an unlock password."
        case .invalidPassword: "Enter a valid, nonempty login password."
        case .passwordValidationFailed: "The password could not be verified for the current Mac account."
        case .authenticationFailed: "System authentication did not authorize Mac Unlock."
        case .cancelled: "Mac Unlock authorization was cancelled."
        case .missingCredential: "No Mac Unlock password is saved."
        case .invalidRecord: "The saved Mac Unlock credential is damaged or unsupported. Delete it and set it up again."
        case .wrongAccount: "This credential belongs to a different Mac account."
        case .bindingMismatch: "The saved password does not belong to this enrolled face."
        case .notArmed: "Authorize Mac Unlock again before using the saved password."
        case .recordChanged: "The saved credential changed. Authorize Mac Unlock again."
        case .persistenceFailed: "The Mac Unlock credential could not be saved, read, or removed."
        case .unsafePermissions: "The Mac Unlock storage location has unsafe ownership or permissions."
        }
    }
}

struct MacUnlockKeyMaterial: Codable, Equatable, Sendable {
    var enclaveHandle: Data
    var peerPublicKey: Data
    var salt: Data
}

struct MacUnlockCreatedKey: Sendable {
    var material: MacUnlockKeyMaterial
    var key: SymmetricKey
}

@MainActor
protocol MacUnlockCredentialKeyProvider: AnyObject {
    func create() async throws -> MacUnlockCreatedKey
    func derive(from material: MacUnlockKeyMaterial) async throws -> SymmetricKey
    func cancel()
}

protocol MacUnlockPasswordValidating: Sendable {
    func validate(_ password: String, accountUID: UInt32) async throws
}

@MainActor
protocol MacUnlockCredentialRecordStore {
    func read() throws -> Data?
    func replace(with data: Data) throws
    func delete() throws
}

/// A separate, device-bound credential. The disk record contains no password or raw key.
/// Authentication retains only a derived key in this process until authorization is revoked.
@MainActor
final class MacUnlockCredentialVault: MacUnlockCredentialAccess {
    static let maximumRecordBytes = 32 * 1024
    private static let maximumPasswordBytes = 1024
    private static let purpose = Data("Notchy.MacUnlock.credential.v1\0".utf8)

    private struct Header: Codable {
        var version: Int
        var binding: MacUnlockBinding
        var keyMaterial: MacUnlockKeyMaterial
    }
    private struct Record: Codable {
        var header: Header
        var ciphertext: Data
    }
    private struct AuthorizedSession {
        var key: SymmetricKey
        var binding: MacUnlockBinding
        var recordDigest: Data
        var lastActivity: Date
    }

    private let store: any MacUnlockCredentialRecordStore
    private let keys: any MacUnlockCredentialKeyProvider
    private let validator: any MacUnlockPasswordValidating
    private let accountUID: () -> UInt32
    private let now: () -> Date
    private let authorizationLifetime: () -> TimeInterval?
    private var record: Record?
    private var session: AuthorizedSession?
    private var generation: UInt64 = 0

    init(
        store: any MacUnlockCredentialRecordStore,
        keys: any MacUnlockCredentialKeyProvider,
        validator: any MacUnlockPasswordValidating,
        accountUID: @escaping () -> UInt32 = { UInt32(getuid()) },
        now: @escaping () -> Date = Date.init,
        authorizationLifetime: @escaping () -> TimeInterval? = { 30 * 86_400 }
    ) {
        self.store = store
        self.keys = keys
        self.validator = validator
        self.accountUID = accountUID
        self.now = now
        self.authorizationLifetime = authorizationLifetime
    }

    static func standard(fileManager: FileManager = .default) throws -> MacUnlockCredentialVault {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MacUnlockVaultError.persistenceFailed
        }
        let url = base.appendingPathComponent(AppPaths.appFolderName, isDirectory: true)
            .appendingPathComponent("MacUnlock", isDirectory: true)
            .appendingPathComponent("credential.sealed", isDirectory: false)
        return MacUnlockCredentialVault(store: MacUnlockCredentialFileStore(fileURL: url),
                                        keys: MacUnlockEnclaveKeyProvider(), validator: MacUnlockAccountPasswordValidator(),
                                        authorizationLifetime: { FaceCheckPreferences.shared.options.sessionLifetime.interval })
    }

    var binding: MacUnlockBinding? { record?.header.binding }

    var isArmed: Bool {
        guard let session else { return false }
        if let limit = authorizationLifetime(),
           !limit.isFinite || limit <= 0 || now().timeIntervalSince(session.lastActivity) >= limit {
            disarm()
            return false
        }
        guard accountUID() == session.binding.accountUID else {
            disarm()
            return false
        }
        return true
    }

    /// Reads bounded metadata only. No key operation, directory password check, or prompt occurs.
    func load() throws {
        disarm()
        record = nil
        if let data = try readStoredData() { record = try decode(data) }
    }

    func save(password: String, binding: MacUnlockBinding) async throws {
        disarm()
        let attempt = generation
        // A structurally malformed record requires an explicit delete, never a silent replacement.
        record = nil
        if let existing = try readStoredData() { record = try decode(existing) }
        try validate(binding)
        guard !password.isEmpty, password.utf8.count <= Self.maximumPasswordBytes,
              !password.utf8.contains(0) else { throw MacUnlockVaultError.invalidPassword }
        do {
            try requireCurrent(attempt, binding: binding)
            try await validator.validate(password, accountUID: binding.accountUID)
            try requireCurrent(attempt, binding: binding)
            let created = try await keys.create()
            try requireCurrent(attempt, binding: binding)
            try validate(created.material)
            let header = Header(version: 1, binding: binding, keyMaterial: created.material)
            var plaintext = Data(password.utf8)
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            let sealed = try AES.GCM.seal(plaintext, using: created.key, authenticating: associatedData(header))
            guard let ciphertext = sealed.combined else { throw MacUnlockVaultError.invalidRecord }
            let next = Record(header: header, ciphertext: ciphertext)
            let data = try Self.encoder().encode(next)
            try requireCurrent(attempt, binding: binding)
            do { try store.replace(with: data) }
            catch { throw Self.storageError(error) }
            record = next
            authorize(created.key, for: next, data: data)
        } catch {
            if generation == attempt { disarm() }
            throw Self.operationError(error)
        }
    }

    func arm() async throws {
        disarm()
        let attempt = generation
        record = nil
        guard let data = try readStoredData() else { throw MacUnlockVaultError.missingCredential }
        let loaded = try decode(data)
        record = loaded
        do {
            try requireCurrent(attempt, binding: loaded.header.binding)
            let key = try await keys.derive(from: loaded.header.keyMaterial)
            try requireCurrent(attempt, binding: loaded.header.binding)
            // Authenticate the whole binding before making either it or its key usable.
            var probe = try open(loaded, using: key)
            probe.resetBytes(in: 0..<probe.count)
            guard try readStoredData() == data else { throw MacUnlockVaultError.recordChanged }
            authorize(key, for: loaded, data: data)
        } catch {
            if generation == attempt { disarm() }
            throw Self.operationError(error)
        }
    }

    func password(for requested: MacUnlockBinding) throws -> Data {
        guard isArmed, let session, let record else { throw MacUnlockVaultError.notArmed }
        guard requested == session.binding, requested == record.header.binding else {
            disarm()
            throw MacUnlockVaultError.bindingMismatch
        }
        do {
            // Check exact authenticated binding before any credential read or decryption.
            guard let data = try readStoredData(), Data(SHA256.hash(data: data)) == session.recordDigest else {
                throw MacUnlockVaultError.recordChanged
            }
            guard isArmed else { throw MacUnlockVaultError.notArmed }
            return try open(record, using: session.key)
        } catch {
            disarm()
            throw Self.operationError(error)
        }
    }

    func disarm() {
        generation &+= 1
        session = nil
        keys.cancel()
    }

    func recordSuccessfulUnlock() {
        guard isArmed else { return }
        session?.lastActivity = now()
    }

    func delete() throws {
        disarm()
        record = nil
        do { try store.delete() }
        catch { throw Self.storageError(error) }
    }

    private func authorize(_ key: SymmetricKey, for record: Record, data: Data) {
        session = AuthorizedSession(key: key, binding: record.header.binding,
                                    recordDigest: Data(SHA256.hash(data: data)), lastActivity: now())
    }

    private func requireCurrent(_ attempt: UInt64, binding: MacUnlockBinding) throws {
        guard generation == attempt, !Task.isCancelled else { throw MacUnlockVaultError.cancelled }
        try validate(binding)
    }

    private func validate(_ binding: MacUnlockBinding) throws {
        guard binding.enrollmentDigest.count == SHA256.byteCount else { throw MacUnlockVaultError.invalidRecord }
        guard binding.accountUID > 0, binding.accountUID == accountUID() else { throw MacUnlockVaultError.wrongAccount }
    }

    private func validate(_ material: MacUnlockKeyMaterial) throws {
        guard !material.enclaveHandle.isEmpty, material.enclaveHandle.count <= 16 * 1024,
              material.peerPublicKey.count == 65, material.salt.count == 32,
              (try? P256.KeyAgreement.PublicKey(x963Representation: material.peerPublicKey)) != nil else {
            throw MacUnlockVaultError.invalidRecord
        }
    }

    private func readStoredData() throws -> Data? {
        do {
            guard let data = try store.read() else { return nil }
            guard data.count <= Self.maximumRecordBytes else { throw MacUnlockVaultError.invalidRecord }
            return data
        } catch { throw Self.storageError(error) }
    }

    private func decode(_ data: Data) throws -> Record {
        guard let decoded = try? JSONDecoder().decode(Record.self, from: data), decoded.header.version == 1,
              (29...(Self.maximumPasswordBytes + 28)).contains(decoded.ciphertext.count) else {
            throw MacUnlockVaultError.invalidRecord
        }
        try validate(decoded.header.binding)
        try validate(decoded.header.keyMaterial)
        return decoded
    }

    private func open(_ record: Record, using key: SymmetricKey) throws -> Data {
        do {
            let sealed = try AES.GCM.SealedBox(combined: record.ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: key, authenticating: associatedData(record.header))
            guard (1...Self.maximumPasswordBytes).contains(plaintext.count) else { throw MacUnlockVaultError.invalidRecord }
            return plaintext
        } catch { throw MacUnlockVaultError.invalidRecord }
    }

    private func associatedData(_ header: Header) throws -> Data { Self.purpose + (try Self.encoder().encode(header)) }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static func storageError(_ error: Error) -> MacUnlockVaultError {
        error as? MacUnlockVaultError ?? .persistenceFailed
    }
    private static func operationError(_ error: Error) -> MacUnlockVaultError {
        if error is CancellationError { return .cancelled }
        return error as? MacUnlockVaultError ?? .authenticationFailed
    }
}

/// A fresh system-authentication context is required for every key creation or recovery.
/// There is deliberately no software-key or file-key fallback.
@MainActor
final class MacUnlockEnclaveKeyProvider: MacUnlockCredentialKeyProvider {
    private var pending: MacUnlockAuthenticationAttempt?
    nonisolated private static let derivationInfo = Data("Notchy.MacUnlock.encryption-key.v1".utf8)

    func cancel() { pending?.invalidate(); pending = nil }

    func create() async throws -> MacUnlockCreatedKey {
        guard SecureEnclave.isAvailable else { throw MacUnlockVaultError.secureEnclaveUnavailable }
        let attempt = begin()
        defer { finish(attempt) }
        return try await withTaskCancellationHandler {
            try await authenticate(attempt)
            return try await Task.detached(priority: .userInitiated) {
                try attempt.checkCancellation()
                guard let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.userPresence, .privateKeyUsage], nil
                ) else { throw MacUnlockVaultError.secureEnclaveUnavailable }
                do {
                    let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access, authenticationContext: attempt.context)
                    let material = MacUnlockKeyMaterial(
                        enclaveHandle: privateKey.dataRepresentation,
                        peerPublicKey: P256.KeyAgreement.PrivateKey().publicKey.x963Representation,
                        salt: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                    )
                    let key = try Self.derive(privateKey, material: material)
                    try attempt.checkCancellation()
                    return MacUnlockCreatedKey(material: material, key: key)
                } catch { throw Self.safeAuthenticationError(error) }
            }.value
        } onCancel: { attempt.invalidate() }
    }

    func derive(from material: MacUnlockKeyMaterial) async throws -> SymmetricKey {
        guard SecureEnclave.isAvailable else { throw MacUnlockVaultError.secureEnclaveUnavailable }
        let attempt = begin()
        defer { finish(attempt) }
        return try await withTaskCancellationHandler {
            try await authenticate(attempt)
            return try await Task.detached(priority: .userInitiated) {
                try attempt.checkCancellation()
                do {
                    let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: material.enclaveHandle,
                                                                                  authenticationContext: attempt.context)
                    let key = try Self.derive(privateKey, material: material)
                    try attempt.checkCancellation()
                    return key
                } catch { throw Self.safeAuthenticationError(error) }
            }.value
        } onCancel: { attempt.invalidate() }
    }

    private func begin() -> MacUnlockAuthenticationAttempt {
        cancel()
        let attempt = MacUnlockAuthenticationAttempt()
        attempt.context.localizedReason = "Authorize the saved login password for Mac Unlock."
        attempt.context.touchIDAuthenticationAllowableReuseDuration = 0
        pending = attempt
        return attempt
    }

    private func finish(_ attempt: MacUnlockAuthenticationAttempt) {
        if pending === attempt { pending = nil }
        attempt.invalidate()
    }

    private func authenticate(_ attempt: MacUnlockAuthenticationAttempt) async throws {
        do {
            try attempt.checkCancellation()
            let allowed = try await attempt.context.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "Authorize Mac Unlock while Notchy is running.")
            try attempt.checkCancellation()
            guard allowed else { throw MacUnlockVaultError.authenticationFailed }
        } catch { throw Self.safeAuthenticationError(error) }
    }

    nonisolated private static func derive(_ key: SecureEnclave.P256.KeyAgreement.PrivateKey,
                                           material: MacUnlockKeyMaterial) throws -> SymmetricKey {
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: material.peerPublicKey)
        return try key.sharedSecretFromKeyAgreement(with: peer).hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: material.salt,
            sharedInfo: derivationInfo, outputByteCount: 32
        )
    }

    nonisolated private static func safeAuthenticationError(_ error: Error) -> MacUnlockVaultError {
        if let error = error as? MacUnlockVaultError { return error }
        if error is CancellationError { return .cancelled }
        if let authentication = error as? LAError,
           [.userCancel, .appCancel, .systemCancel, .invalidContext].contains(authentication.code) { return .cancelled }
        return .authenticationFailed
    }
}

/// The context is used by one authentication/key operation; invalidate may interrupt it from
/// the main actor, as supported by LocalAuthentication. Its cancellation flag is lock-protected.
private final class MacUnlockAuthenticationAttempt: @unchecked Sendable {
    let context = LAContext()
    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    func invalidate() {
        cancelled.withLock { $0 = true }
        context.invalidate()
    }
    func checkCancellation() throws {
        guard !cancelled.withLock({ $0 }) else { throw MacUnlockVaultError.cancelled }
    }
}

struct MacUnlockAccountPasswordValidator: MacUnlockPasswordValidating {
    func validate(_ password: String, accountUID: UInt32) async throws {
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            guard accountUID == getuid(), getuid() == geteuid(), accountUID > 0 else { throw MacUnlockVaultError.wrongAccount }
            do {
                let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeAuthentication))
                let user = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: [kODAttributeTypeUniqueID])
                let identifiers = try user.values(forAttribute: kODAttributeTypeUniqueID) as? [String]
                guard identifiers?.contains(String(accountUID)) == true else { throw MacUnlockVaultError.wrongAccount }
                try user.verifyPassword(password)
            } catch let error as MacUnlockVaultError { throw error }
            catch { throw MacUnlockVaultError.passwordValidationFailed }
        }.value
    }
}

/// One atomic envelope avoids mismatched key/ciphertext files after a crash. File descriptors
/// refuse symlinks; the credential directory and every persisted file are owner-only.
@MainActor
struct MacUnlockCredentialFileStore: MacUnlockCredentialRecordStore {
    let fileURL: URL

    func read() throws -> Data? {
        guard let directory = try openDirectory(create: false) else { return nil }
        defer { close(directory) }
        let descriptor = openat(directory, fileURL.lastPathComponent, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw MacUnlockVaultError.persistenceFailed
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1 else {
            throw MacUnlockVaultError.unsafePermissions
        }
        guard info.st_size > 0, info.st_size <= MacUnlockCredentialVault.maximumRecordBytes else { throw MacUnlockVaultError.invalidRecord }
        var data = Data(count: Int(info.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw MacUnlockVaultError.invalidRecord }
                offset += count
            }
        }
        var extra: UInt8 = 0
        var remaining: Int
        repeat { remaining = Darwin.read(descriptor, &extra, 1) } while remaining < 0 && errno == EINTR
        guard remaining == 0 else { throw MacUnlockVaultError.invalidRecord }
        return data
    }

    func replace(with data: Data) throws {
        guard !data.isEmpty, data.count <= MacUnlockCredentialVault.maximumRecordBytes,
              let directory = try openDirectory(create: true) else { throw MacUnlockVaultError.persistenceFailed }
        defer { close(directory) }
        let temporary = ".credential-\(UUID().uuidString).tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw MacUnlockVaultError.persistenceFailed }
        defer { close(descriptor); _ = unlinkat(directory, temporary, 0) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw MacUnlockVaultError.persistenceFailed }
                offset += count
            }
        }
        guard fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0,
              renameat(directory, temporary, directory, fileURL.lastPathComponent) == 0,
              fsync(directory) == 0 else { throw MacUnlockVaultError.persistenceFailed }
    }

    func delete() throws {
        guard let directory = try openDirectory(create: false) else { return }
        defer { close(directory) }
        guard unlinkat(directory, fileURL.lastPathComponent, 0) == 0 || errno == ENOENT else { throw MacUnlockVaultError.persistenceFailed }
        guard fsync(directory) == 0 else { throw MacUnlockVaultError.persistenceFailed }
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        var folder = fileURL.deletingLastPathComponent()
        if create {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            } catch { throw MacUnlockVaultError.persistenceFailed }
        }
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw MacUnlockVaultError.persistenceFailed
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw MacUnlockVaultError.unsafePermissions
        }
        if create {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        return descriptor
    }
}
