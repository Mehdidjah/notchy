@preconcurrency import AVFoundation
import CryptoKit
import Foundation

enum MacUnlockScanResult: Equatable, Sendable {
    case verified
    case failed(String)
    case cancelled
}

@MainActor
protocol MacUnlockScanning: AnyObject {
    func scan(identity: FaceIdentity, prompt: @escaping @MainActor (String) -> Void) async -> MacUnlockScanResult
    func cancel()
}

/// A lock-screen check owns its camera independently of previews and in-app approvals.
/// It never asks for camera permission while locked, and never exports camera images.
@MainActor
final class MacUnlockFaceScanner: MacUnlockScanning {
    private let camera: any FaceCheckCameraCapturing
    private let embedder = FaceEmbedder(profile: .auraFace)
    private let modelPolicy: FaceUnlockModelPolicy
    private let prepareModels: (@Sendable () async throws -> Void)?
    private lazy var pipeline = FaceCheckPipeline(embedder: embedder)
    private let timeout: Duration
    private var epoch = 0
    private var startedAt: TimeInterval = 0
    private var verification: FacePassiveVerificationSession?
    private var continuation: CheckedContinuation<MacUnlockScanResult, Never>?
    private var prompt: (@MainActor (String) -> Void)?
    private var deadline: Task<Void, Never>?
    private var preparation: Task<Void, Never>?

    init(camera: any FaceCheckCameraCapturing = FaceCheckCamera(), timeout: Duration = .seconds(10),
         modelPolicy: FaceUnlockModelPolicy = .current,
         prepareModels: (@Sendable () async throws -> Void)? = nil) {
        self.camera = camera
        self.timeout = timeout
        self.modelPolicy = modelPolicy
        self.prepareModels = prepareModels
    }

    func scan(identity: FaceIdentity, prompt: @escaping @MainActor (String) -> Void) async -> MacUnlockScanResult {
        cancel()
        guard !Task.isCancelled else { return .cancelled }
        guard camera.authorizationStatus == .authorized else {
            return .failed("Allow camera access in Face Check settings first.")
        }
        guard identity.supportsPassiveUnlock else { return .failed("Scan your face again to use the new Face Unlock model.") }
        guard let profile = modelPolicy.recognitionProfile else { return .failed(FaceModelValidation.unavailableMessage) }
        let matcher = FaceMatcher(identities: [identity], profile: profile)
        guard matcher.hasComparableIdentities else { return .failed("Enroll your face again before enabling Mac unlock.") }
        epoch &+= 1
        let token = epoch
        verification = FacePassiveVerificationSession(matcher: matcher, generation: token,
                                                       configuration: modelPolicy.verificationConfiguration)
        startedAt = ProcessInfo.processInfo.systemUptime
        self.prompt = prompt
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.cancelled, token: token); return }
                prompt("Checking your face…")
                let pipeline = pipeline
                let prepareModels = prepareModels
                preparation = Task { [weak self] in
                    do {
                        if let prepareModels { try await prepareModels() }
                        else { try await pipeline.prepare(passive: true) }
                    }
                    catch {
                        self?.finish(.failed("The face models could not start. Enter your password."), token: token)
                        return
                    }
                    guard !Task.isCancelled, let self, epoch == token, self.continuation != nil else { return }
                    startedAt = ProcessInfo.processInfo.systemUptime
                    camera.start(onFrame: { [weak self] image, capturedAt in
                        let frame = await pipeline.analyze(image, capturedAt: capturedAt, generation: token, passive: true)
                        await self?.consume(frame, token: token)
                    }, completion: { [weak self] started in
                        guard !started else { return }
                        Task { @MainActor in self?.finish(.failed("The camera is unavailable. Enter your password."), token: token) }
                    })
                }
                deadline = Task { [weak self, timeout] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failed("Face not recognized. Hover to try again."), token: token)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.cancelled, token: token) }
        }
    }

    func cancel() { finish(.cancelled, token: epoch) }

    private func consume(_ analysis: FaceFrameAnalysis, token: Int) {
        guard token == epoch, continuation != nil, var verification,
              let captured = analysis.capturedAt, captured.isFinite, captured >= startedAt else { return }
        let age = ProcessInfo.processInfo.systemUptime - captured
        guard (0...1).contains(age) else {
            finish(.failed("The camera was interrupted. Hover to try again."), token: token)
            return
        }
        let result = verification.consume(analysis, timestamp: captured)
        self.verification = verification
        switch result {
        case .waiting(let text): prompt?(text)
        case .recognized: finish(.verified, token: token)
        case .rejected(let text): finish(.failed(text), token: token)
        }
    }

    private func finish(_ result: MacUnlockScanResult, token: Int) {
        guard token == epoch else { return }
        epoch &+= 1
        let pending = continuation
        continuation = nil
        verification = nil
        prompt = nil
        deadline?.cancel()
        deadline = nil
        preparation?.cancel()
        preparation = nil
        camera.stop()
        pending?.resume(returning: result)
        let finishedEpoch = epoch
        Task { [weak self] in
            guard let self, epoch == finishedEpoch, continuation == nil else { return }
            await pipeline.unload()
        }
    }
}

@MainActor
protocol MacUnlockEnrollmentReading: AnyObject {
    func identity(for binding: MacUnlockBinding) async throws -> FaceIdentity
}

enum MacUnlockEnrollmentError: LocalizedError {
    case changed
    case validationPending
    var errorDescription: String? {
        switch self {
        case .changed: "The saved face changed. Scan again and set up Mac unlock."
        case .validationPending: FaceModelValidation.unavailableMessage
        }
    }
}

extension MacUnlockBinding {
    static func enrolling(_ identity: FaceIdentity, userID: UInt32 = getuid()) throws -> MacUnlockBinding {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return MacUnlockBinding(identityID: identity.id,
                                enrollmentDigest: Data(SHA256.hash(data: try encoder.encode(identity))),
                                accountUID: userID)
    }
}

@MainActor
final class MacUnlockEnrollmentReader: MacUnlockEnrollmentReading {
    private var store: FaceEnrollmentStore?
    private let modelPolicy: FaceUnlockModelPolicy

    init(modelPolicy: FaceUnlockModelPolicy = .current) { self.modelPolicy = modelPolicy }

    func identity(for binding: MacUnlockBinding) async throws -> FaceIdentity {
        guard modelPolicy.allowsUnlock else { throw MacUnlockEnrollmentError.validationPending }
        guard binding.accountUID == getuid() else { throw MacUnlockEnrollmentError.changed }
        let store: FaceEnrollmentStore
        if let existing = self.store { store = existing }
        else {
            store = FaceEnrollmentStore(fileURL: try FaceEnrollmentStore.defaultFileURL(),
                                        keyProvider: try FaceCheckKeyStorage.standard())
            self.store = store
        }
        guard case .ready(let identities) = await store.load(),
              let identity = identities.first(where: { $0.id == binding.identityID }), identity.isEnabled,
              identity.supportsPassiveUnlock,
              try MacUnlockBinding.enrolling(identity) == binding else { throw MacUnlockEnrollmentError.changed }
        return identity
    }
}
