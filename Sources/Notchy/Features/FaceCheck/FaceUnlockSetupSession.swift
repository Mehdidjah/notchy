import Combine
import Foundation

/// Connects a successfully persisted face to credential setup. This object never stores
/// the entered password; the view clears its field when handing it to the credential task.
@MainActor
final class FaceUnlockSetupSession: ObservableObject {
    enum Stage: Equatable {
        case inactive, capturing, faceSaved, password, permission, complete
        var showsCredentialStep: Bool { self == .password || self == .permission || self == .complete }
    }
    @Published private(set) var stage: Stage = .inactive
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    private(set) var identity: FaceIdentity?
    var onFinished: (() -> Void)?
    var unavailableReason: String? { unlock.setupUnavailableReason }
    var isExperimental: Bool { unlock.isExperimental }

    private let unlock: MacUnlockController
    private let savedHold: Duration
    private let completionHold: Duration
    private var pending: Task<Void, Never>?
    private var epoch = 0
    private var isActive = false
    private var changes: AnyCancellable?

    init(unlock: MacUnlockController, savedHold: Duration = .milliseconds(1_200),
         completionHold: Duration = .milliseconds(1_400)) {
        self.unlock = unlock
        self.savedHold = savedHold
        self.completionHold = completionHold
        changes = unlock.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.reconcilePermission()
        }
    }

    func beginCapture() {
        reset()
        isActive = true
        stage = .capturing
    }

    func saved(_ identity: FaceIdentity) {
        guard isActive, stage == .capturing else { return }
        self.identity = identity
        stage = .faceSaved
        let token = epoch
        pending = Task { [weak self, savedHold] in
            try? await Task.sleep(for: savedHold)
            guard !Task.isCancelled, let self, epoch == token else { return }
            stage = .password
            pending = nil
        }
    }

    func submit(password: String) {
        if let reason = unavailableReason { error = reason; return }
        guard isActive, stage == .password, !isSaving, !password.isEmpty, let identity else { return }
        guard !unlock.isBusy else { error = "Finish the current password setup first."; return }
        isSaving = true
        error = nil
        let token = epoch
        pending = Task { [weak self] in
            guard let self else { return }
            await unlock.save(password: password, identity: identity)
            guard !Task.isCancelled, epoch == token else { return }
            isSaving = false
            pending = nil
            guard credentialIsReady else {
                if case .failed(let message) = unlock.state { error = message }
                else { error = "Your password could not be saved. Please try again." }
                return
            }
            if unlock.accessibilityGranted { finish() }
            else { stage = .permission }
        }
    }

    func refreshPermission() {
        unlock.refreshReadiness()
        reconcilePermission()
    }

    /// Keep the last visual stage during panel collapse, but invalidate every delayed step.
    func cancel() {
        isActive = false
        epoch &+= 1
        pending?.cancel()
        pending = nil
        if isSaving { unlock.cancelSetup() }
        isSaving = false
    }

    func reset() {
        cancel()
        identity = nil
        error = nil
        stage = .inactive
    }

    private var credentialIsReady: Bool {
        unlock.hasPassword && unlock.isAuthorized && unlock.isEnabled && unlock.state == .ready
            && unlock.boundIdentityID == identity?.id
    }

    private func reconcilePermission() {
        guard isActive, stage == .permission else { return }
        guard credentialIsReady else {
            stage = .password
            error = "Face Unlock changed. Save your password again to continue."
            return
        }
        if unlock.accessibilityGranted { finish() }
    }

    private func finish() {
        stage = .complete
        let token = epoch
        pending = Task { [weak self, completionHold] in
            try? await Task.sleep(for: completionHold)
            guard !Task.isCancelled, let self, epoch == token else { return }
            onFinished?()
        }
    }
}
