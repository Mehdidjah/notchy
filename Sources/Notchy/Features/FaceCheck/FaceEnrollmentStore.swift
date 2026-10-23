import CryptoKit
import Foundation

/// Supplies the key that seals Face Check's enrolment file.
///
/// Where the key lives (and whether reading it asks for Touch ID or a password) is the
/// provider's business, so the store never changes when that decision does. Calls are
/// synchronous and made from the store's own actor, never the main actor; a provider that needs
/// the user to authenticate should have that done before the store is asked for anything.
protocol FaceCheckKeyProvider: Sendable {
    /// The stored key, or `nil` when there is none (never created, or deleted). Throws when the
    /// key may exist but cannot be read right now.
    func existingKey() throws -> SymmetricKey?
    /// Makes and stores a new key, replacing any previous one.
    func createKey() throws -> SymmetricKey
    /// Removes the stored key. Succeeds when there is none.
    func deleteKey() throws
}

/// Why the enrolment file could not be read. The file is left exactly as it is in every case.
enum FaceEnrollmentUnreadableReason: Equatable, Sendable {
    /// The file exists but its key is gone, for example after the keychain was reset.
    case keyMissing
    /// The key provider failed; this may pass, so loading can be tried again.
    case keyUnavailable(String)
    /// The file could not be read from disk; this may pass too.
    case fileUnavailable(String)
    /// The key does not open the file, or the file is damaged.
    case cannotDecrypt
    /// It decrypted but is not a store Face Check understands.
    case damaged
    /// Written by a newer version of Notchy.
    case unsupportedVersion(Int)

    /// Whether the faces are lost for good and need enrolling again (after the user agrees to
    /// remove the old file), as opposed to a failure worth retrying.
    var requiresReenrolment: Bool {
        switch self {
        case .keyMissing, .cannotDecrypt, .damaged: true
        case .keyUnavailable, .fileUnavailable, .unsupportedVersion: false
        }
    }
}

enum FaceEnrollmentStoreState: Equatable, Sendable {
    case notLoaded
    /// Loaded; empty when nothing has been enrolled.
    case ready([FaceIdentity])
    case unreadable(FaceEnrollmentUnreadableReason)
}

enum FaceEnrollmentStoreError: Error, Equatable {
    /// The existing file could not be read, so it is not overwritten. `deleteAll()` clears it.
    case unreadable(FaceEnrollmentUnreadableReason)
    case keyUnavailable(String)
    case writeFailed(String)
    case deleteFailed(String)
}

/// Face Check's enrolled identities, sealed with AES-GCM in Notchy's Application Support folder.
///
/// What is stored: names, descriptors and how each sample was captured, as JSON, encrypted and
/// authenticated as one blob. Never an image. The file is only ever replaced whole through an
/// atomic rename, so a crash mid-save leaves the previous version.
///
/// A file that cannot be opened is never overwritten: a key lost to a keychain reset (common for
/// a rebuilt, ad-hoc signed app) must not silently turn into an empty store. The state becomes
/// `unreadable` and every save is refused until the file reads cleanly again (a locked keychain
/// unlocking) or an explicit `deleteAll()` removes it so the user can enrol again.
///
/// The key provider is called on this actor, never on the main actor, so a slow keychain read
/// cannot stall the interface.
actor FaceEnrollmentStore {
    static let folderName = "FaceCheck"
    static let fileName = "identities.sealed"
    /// Bumped when the stored JSON changes shape.
    static let currentVersion = 1
    /// Ties the sealed bytes to this purpose, so a blob sealed by the same key for anything else
    /// cannot be passed off as an enrolment file.
    static let associatedData = Data("Notchy.FaceCheck.identities".utf8)

    /// `Application Support/Notchy/FaceCheck/identities.sealed`.
    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        fileURL(inAppSupportDirectory: try AppPaths.applicationSupportDirectory(fileManager: fileManager))
    }

    /// Where the file lives inside a given app support folder (Notchy's own, or a test's).
    static func fileURL(inAppSupportDirectory directory: URL) -> URL {
        directory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    let fileURL: URL
    private let keyProvider: any FaceCheckKeyProvider
    private(set) var state: FaceEnrollmentStoreState = .notLoaded

    init(fileURL: URL, keyProvider: any FaceCheckKeyProvider) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    // MARK: Reading

    /// Reads the file again and returns the resulting state. A missing file is an empty store.
    @discardableResult
    func load() -> FaceEnrollmentStoreState {
        state = readState()
        return state
    }

    /// The enrolled identities, reading the file first if it has not been read yet or was
    /// unreadable last time. Throws `unreadable` while the file still cannot be opened.
    func identities() throws -> [FaceIdentity] {
        switch loadedState() {
        case .ready(let identities): return identities
        case .unreadable(let reason): throw FaceEnrollmentStoreError.unreadable(reason)
        case .notLoaded: return []
        }
    }

    // MARK: Writing

    /// Replaces everything stored with `identities`.
    func replaceAll(with identities: [FaceIdentity]) throws {
        if case .unreadable(let reason) = loadedState() {
            throw FaceEnrollmentStoreError.unreadable(reason)
        }
        let key: SymmetricKey
        do {
            key = try keyProvider.existingKey() ?? keyProvider.createKey()
        } catch {
            throw FaceEnrollmentStoreError.keyUnavailable(error.localizedDescription)
        }
        do {
            let envelope = Envelope(version: Self.currentVersion, identities: identities)
            let plaintext = try JSONEncoder().encode(envelope)
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: Self.associatedData)
            guard let combined = sealed.combined else {
                throw FaceEnrollmentStoreError.writeFailed("The sealed data has no combined form.")
            }
            try write(combined)
        } catch let error as FaceEnrollmentStoreError {
            throw error
        } catch {
            throw FaceEnrollmentStoreError.writeFailed(error.localizedDescription)
        }
        state = .ready(identities)
    }

    /// Adds `identity`, or replaces the stored one with the same id.
    func upsert(_ identity: FaceIdentity) throws {
        var all = try identities()
        if let index = all.firstIndex(where: { $0.id == identity.id }) {
            all[index] = identity
        } else {
            all.append(identity)
        }
        try replaceAll(with: all)
    }

    func removeIdentity(id: UUID) throws {
        let all = try identities()
        guard all.contains(where: { $0.id == id }) else { return }
        try replaceAll(with: all.filter { $0.id != id })
    }

    /// Mutates only current metadata; never writes stale samples back over a newer enrollment.
    func setEnabled(_ enabled: Bool, id: UUID) throws {
        var all = try identities()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].isEnabled = enabled
        try replaceAll(with: all)
    }

    func recapture(_ identity: FaceIdentity, replacing previous: FaceIdentity) throws {
        var all = try identities()
        guard let index = all.firstIndex(of: previous), identity.id == previous.id else {
            throw FaceEnrollmentStoreError.writeFailed("The saved face changed during capture. Start again.")
        }
        all[index] = identity
        try replaceAll(with: all)
    }

    /// Removes the file and then its key, whatever state the store is in. This is the way out of
    /// an `unreadable` file that will never open again (`requiresReenrolment`), and it should only
    /// run when the user asks for it. If only the key removal fails the faces are already gone, so
    /// the store is empty either way and the error just reports the leftover key.
    func deleteAll() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                throw FaceEnrollmentStoreError.deleteFailed(error.localizedDescription)
            }
        }
        state = .ready([])
        do {
            try keyProvider.deleteKey()
        } catch {
            throw FaceEnrollmentStoreError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: Private

    private struct Envelope: Codable {
        var version: Int
        var identities: [FaceIdentity]
    }

    /// Only the version, so a file from a newer Notchy is recognised before its body is decoded.
    private struct VersionProbe: Decodable {
        var version: Int
    }

    /// The current state, reading the file first when it has not been read or could not be read
    /// last time. Retrying an unreadable file is cheap and lets a passing failure (a locked
    /// keychain, a busy disk) clear by itself; it never writes, so it cannot make things worse.
    private func loadedState() -> FaceEnrollmentStoreState {
        switch state {
        case .notLoaded, .unreadable: return load()
        case .ready: return state
        }
    }

    private func readState() -> FaceEnrollmentStoreState {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return .ready([]) }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .unreadable(.fileUnavailable(error.localizedDescription))
        }

        let key: SymmetricKey
        do {
            guard let existing = try keyProvider.existingKey() else { return .unreadable(.keyMissing) }
            key = existing
        } catch {
            return .unreadable(.keyUnavailable(error.localizedDescription))
        }

        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            plaintext = try AES.GCM.open(box, using: key, authenticating: Self.associatedData)
        } catch {
            return .unreadable(.cannotDecrypt)
        }

        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: plaintext) else {
            return .unreadable(.damaged)
        }
        guard probe.version <= Self.currentVersion else {
            return .unreadable(.unsupportedVersion(probe.version))
        }
        guard let envelope = try? decoder.decode(Envelope.self, from: plaintext) else {
            return .unreadable(.damaged)
        }
        return .ready(envelope.identities)
    }

    /// Writes a temporary file next to the real one and renames it over the top, so a reader
    /// sees either the old file or the new one, never half of either. The temporary file is
    /// created owner-only before any bytes go in, so there is no moment when the sealed data is
    /// readable by others, whatever the folder's permissions.
    private func write(_ data: Data) throws {
        let fileManager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = folder.appendingPathComponent(".\(Self.fileName).\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw FaceEnrollmentStoreError.writeFailed("Could not create a temporary file in \(folder.path).")
        }
        do {
            try data.write(to: temporary)
            guard rename(temporary.path, fileURL.path) == 0 else {
                throw FaceEnrollmentStoreError.writeFailed(String(cString: strerror(errno)))
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
