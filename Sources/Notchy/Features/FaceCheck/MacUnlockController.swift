import AppKit
import Combine
import Foundation
import os

@MainActor
protocol MacUnlockPresenting: AnyObject {
    func configure(options: FaceCheckOptions)
    func show(activity: FaceCheckLiveActivity) -> Bool
    func didUnlock()
    func hide()
    func collapse()
}

extension MacUnlockPresenting {
    func collapse() { hide() }
    func configure(options: FaceCheckOptions) {}
}

enum MacUnlockEvent { case poll, lock, unlock, wake, sleep, sessionChanged, space }

/// Separate from in-app authorization: a successful clipboard check can never type a password.
@MainActor
final class MacUnlockController: ObservableObject {
    enum State: Equatable {
        case off, needsSetup, needsAuthorization, ready, scanning, submitting, unlocked
        case failed(String)
    }

    static let shared = production()
    @Published private(set) var state: State = .off
    @Published private(set) var isEnabled: Bool
    @Published private(set) var hasPassword = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var isBusy = false
    @Published private(set) var accessibilityGranted = false
    let activity = FaceCheckLiveActivity()

    private let vault: (any MacUnlockCredentialAccess)?
    private let platform: any MacUnlockPlatform
    private let scanner: any MacUnlockScanning
    private let enrollments: any MacUnlockEnrollmentReading
    private let presenter: any MacUnlockPresenting
    private let persistEnabled: (Bool) -> Void
    private let confirmationTimeout: Duration
    private let modelPolicy: FaceUnlockModelPolicy
    private let logger = Logger(subsystem: "com.local.Notchy", category: "MacUnlock")
    var setupUnavailableReason: String? { modelPolicy.unavailableReason }
    var isExperimental: Bool { modelPolicy.isExperimental }
    private var monitor: MacUnlockMonitor?
    private var attemptTask: Task<Void, Never>?
    private var generation = 0
    private var setupGeneration = 0
    private var setupBinding: MacUnlockBinding?
    private var lockedSession: MacUnlockSession?
    private var attemptedAutomatic = false
    private var submittedThisLock = false
    private var scansThisLock = 0
    private var sleeping = false
    private var lastWake = -Double.infinity
    private var running = false
    private var options: FaceCheckOptions
    private var preferenceObserver: AnyCancellable?
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryUsed = false
    private let automaticRetryDelay: Duration
    var onLock: (() -> Void)?
    var boundIdentityID: UUID? { vault?.binding?.identityID }
    var canRemovePassword: Bool {
        guard vault != nil else { return false }
        if hasPassword { return true }
        if case .failed = state { return true }
        return false
    }

    init(vault: (any MacUnlockCredentialAccess)?, platform: any MacUnlockPlatform,
         scanner: any MacUnlockScanning, enrollments: any MacUnlockEnrollmentReading,
         presenter: any MacUnlockPresenting, enabled: Bool = false,
         confirmationTimeout: Duration = .seconds(4), persistEnabled: @escaping (Bool) -> Void = { _ in },
         modelPolicy: FaceUnlockModelPolicy = .current, preferences: FaceCheckPreferences? = nil,
         automaticRetryDelay: Duration = .seconds(1)) {
        self.vault = vault
        self.platform = platform
        self.scanner = scanner
        self.enrollments = enrollments
        self.presenter = presenter
        self.isEnabled = enabled
        self.confirmationTimeout = confirmationTimeout
        self.persistEnabled = persistEnabled
        self.modelPolicy = modelPolicy
        self.options = preferences?.options ?? FaceCheckOptions()
        self.automaticRetryDelay = automaticRetryDelay
        activity.hapticsEnabled = { [weak self] in self?.options.haptics == true }
        activity.retryOnHover = { [weak self] in self?.options.retryOnHover == true }
        activity.onRetry = { [weak self] in self?.retry() }
        activity.onCancel = { [weak self] in self?.cancelScan() }
        activity.onExpired = { [weak self] in
            guard let self else { return }
            self.presenter.collapse()
            if self.state == .unlocked { self.state = .ready; self.refreshReadiness() }
        }
        preferenceObserver = preferences?.$options.dropFirst().sink { [weak self] next in
            guard let self, next != options else { return }
            options = next
            // A pending result belongs to its original settings, including a camera choice.
            invalidateAttempt()
            state = .ready
            refreshReadiness()
        }
    }

    private static func production() -> MacUnlockController {
        let defaults = UserDefaults.standard
        let policy = FaceUnlockModelPolicy.current
        return MacUnlockController(vault: try? MacUnlockCredentialVault.standard(),
            platform: SystemMacUnlockPlatform(), scanner: MacUnlockFaceScanner(modelPolicy: policy),
            enrollments: MacUnlockEnrollmentReader(modelPolicy: policy), presenter: MacUnlockWindowController(),
            enabled: defaults.bool(forKey: "faceCheck.macUnlockEnabled"),
            persistEnabled: { defaults.set($0, forKey: "faceCheck.macUnlockEnabled") },
            modelPolicy: policy, preferences: .shared)
    }

    func start() {
        guard !running else { return }
        running = true
        logger.info("Mac unlock model policy: \(String(describing: self.modelPolicy.mode), privacy: .public)")
        if vault == nil { state = .failed("Secure credential storage is unavailable on this Mac.") }
        do { try vault?.load() }
        catch { state = .failed(error.localizedDescription) }
        refreshReadiness()
        let monitor = MacUnlockMonitor { [weak self] in self?.handle($0) }
        self.monitor = monitor
        monitor.start()
    }

    func stop() {
        running = false
        monitor?.stop()
        monitor = nil
        setupGeneration &+= 1
        setupBinding = nil
        invalidateAttempt()
        vault?.disarm()
        isBusy = false
        refreshReadiness()
    }

    func refreshReadiness() {
        hasPassword = vault?.binding != nil
        isAuthorized = vault?.isArmed == true
        accessibilityGranted = platform.accessibilityGranted
        guard state != .scanning, state != .submitting, state != .unlocked else { return }
        if case .failed = state { return }
        if isEnabled, let reason = setupUnavailableReason { state = .failed(reason); return }
        state = !isEnabled ? .off : (!hasPassword ? .needsSetup : (!isAuthorized ? .needsAuthorization : .ready))
        if isEnabled, !options.livenessEnabled { state = .failed("Turn on liveness detection to resume Face Unlock.") }
    }

    func save(password: String, identity: FaceIdentity) async {
        guard !Task.isCancelled else { return }
        if let reason = setupUnavailableReason { state = .failed(reason); return }
        if !identity.isEnabled || !identity.supportsPassiveUnlock {
            state = .failed("Scan your face again before saving a password for Face Unlock.")
            return
        }
        guard !isBusy, let vault else { return }
        guard let session = unlockedSetupSession(action: "setting up") else { return }
        isBusy = true
        setupGeneration &+= 1
        let token = setupGeneration
        invalidateAttempt()
        defer { if setupGeneration == token { setupBinding = nil; isBusy = false; refreshReadiness() } }
        do {
            var bytes = Data(password.utf8)
            defer { bytes.resetBytes(in: 0..<bytes.count) }
            let plan = try MacUnlockPasswordPlan(password: bytes)
            plan.erase()
            let binding = try MacUnlockBinding.enrolling(identity)
            setupBinding = binding
            _ = try await enrollments.identity(for: binding)
            guard setupGeneration == token, !Task.isCancelled else { return }
            guard stillInSetupSession(session) else { vault.disarm(); return }
            try await vault.save(password: password, binding: binding)
            guard setupGeneration == token else { return }
            guard !Task.isCancelled else { vault.disarm(); return }
            _ = try await enrollments.identity(for: binding)
            guard setupGeneration == token else { return }
            guard !Task.isCancelled, stillInSetupSession(session) else {
                vault.disarm(); return
            }
            isEnabled = true
            persistEnabled(true)
            state = .ready
            logger.info("Mac unlock password linked to the saved face and authorized")
        } catch {
            guard setupGeneration == token else { return }
            vault.disarm()
            state = .failed(error.localizedDescription)
        }
    }

    func authorizeSession() async {
        guard !Task.isCancelled else { return }
        if let reason = setupUnavailableReason { state = .failed(reason); return }
        guard !isBusy, let vault, hasPassword else { return }
        guard let session = unlockedSetupSession(action: "authorizing") else { return }
        isBusy = true
        setupGeneration &+= 1
        let token = setupGeneration
        setupBinding = vault.binding
        defer { if setupGeneration == token { setupBinding = nil; isBusy = false; refreshReadiness() } }
        do {
            try await vault.arm()
            guard setupGeneration == token else { return }
            guard !Task.isCancelled else { vault.disarm(); return }
            guard let binding = vault.binding else { throw MacUnlockEnrollmentError.changed }
            _ = try await enrollments.identity(for: binding)
            guard setupGeneration == token else { return }
            guard !Task.isCancelled, stillInSetupSession(session) else {
                vault.disarm(); return
            }
            isEnabled = true
            persistEnabled(true)
            state = .ready
            logger.info("Mac unlock authorized for the current process")
        } catch {
            guard setupGeneration == token else { return }
            vault.disarm()
            state = .failed(error.localizedDescription)
        }
    }

    private func unlockedSetupSession(action: String) -> MacUnlockSession? {
        switch platform.screenState {
        case .unlocked(let session): return session
        case .locked:
            state = .failed("Unlock your Mac before \(action) Face Unlock.")
        case .unavailable:
            state = .failed("Notchy couldn't verify your current Mac session. Try again from your unlocked desktop.")
        }
        return nil
    }

    private func stillInSetupSession(_ session: MacUnlockSession) -> Bool {
        guard platform.screenState == .unlocked(session) else {
            state = .failed("Your Mac session changed. Unlock your Mac and try again.")
            return false
        }
        return true
    }

    func disable() {
        setupGeneration &+= 1
        setupBinding = nil
        isBusy = false
        isEnabled = false
        persistEnabled(false)
        invalidateAttempt()
        vault?.disarm()
        state = .off
        refreshReadiness()
    }

    func lockAuthorization() {
        cancelSetup()
        invalidateAttempt()
        vault?.disarm()
        state = .needsAuthorization
        refreshReadiness()
    }

    /// Revokes only an in-flight setup operation. Closing an idle setup surface does not
    /// pause a credential the owner has already saved and authorized.
    func cancelSetup() {
        guard isBusy else { return }
        setupGeneration &+= 1
        setupBinding = nil
        isBusy = false
        vault?.disarm()
        state = .off
        refreshReadiness()
    }

    func removePassword() {
        disable()
        do { try vault?.delete(); state = .off }
        catch { state = .failed(error.localizedDescription) }
        refreshReadiness()
    }

    /// Called synchronously when the in-app enrollment store publishes a change. A deletion
    /// completing during input must revoke later batches, not wait for the next camera scan.
    func enrollmentsChanged(_ identities: [FaceIdentity]) {
        guard let binding = setupBinding ?? vault?.binding else { return }
        if let identity = identities.first(where: { $0.id == binding.identityID }), identity.isEnabled,
           (try? MacUnlockBinding.enrolling(identity)) == binding { return }
        setupGeneration &+= 1
        setupBinding = nil
        isBusy = false
        vault?.disarm()
        invalidateAttempt()
        state = .failed("The enrolled face changed. Set up Mac unlock again.")
        refreshReadiness()
    }

    /// Notifications only request a fresh read. They never authorize the camera or credentials.
    func handle(_ event: MacUnlockEvent) {
        defer {
            let listen = running && !sleeping && options.onSpace && options.livenessEnabled
                && isEnabled && vault?.isArmed == true && lockedSession != nil
            monitor?.setSpaceEnabled(listen)
        }
        if event == .sleep {
            sleeping = true
            invalidateAttempt()
            refreshReadiness()
            return
        }
        if event == .wake {
            let resumingFromSleep = sleeping
            sleeping = false
            let now = ProcessInfo.processInfo.systemUptime
            // A real sleep ends the previous wake burst, even if the lid reopens quickly.
            // Duplicate display/system wake signals still cannot replace an active scan.
            if resumingFromSleep || now - lastWake > 1.5 {
                if state != .scanning, state != .submitting { attemptedAutomatic = false }
            }
            lastWake = now
        }
        guard !sleeping else { return }
        accessibilityGranted = platform.accessibilityGranted
        isAuthorized = vault?.isArmed == true
        switch platform.screenState {
        case .unavailable:
            if lockedSession != nil || state == .scanning || state == .submitting { invalidateAttempt() }
            if event == .sessionChanged { vault?.disarm() }
            refreshReadiness()
        case .unlocked(let session):
            if state == .submitting, lockedSession == session, submittedThisLock {
                finishUnlock()
            } else if state == .scanning || lockedSession != nil {
                invalidateAttempt()
            }
            lockedSession = nil
            attemptedAutomatic = false
            submittedThisLock = false
            scansThisLock = 0
            automaticRetryUsed = false
            refreshReadiness()
        case .locked(let session):
            let discoveredLock = lockedSession != session
            if lockedSession != session {
                invalidateAttempt()
                lockedSession = session
                attemptedAutomatic = false
                submittedThisLock = false
                scansThisLock = 0
                automaticRetryUsed = false
                onLock?()
            }
            guard modelPolicy.allowsUnlock, options.livenessEnabled, isEnabled, !isBusy, isAuthorized,
                  vault?.binding?.accountUID == session.userID else {
                if state == .scanning || state == .submitting { invalidateAttempt() }
                refreshReadiness()
                return
            }
            guard accessibilityGranted else {
                invalidateAttempt()
                state = .failed("Allow Accessibility in System Settings to enable Mac unlock.")
                return
            }
            if event == .space {
                if options.onSpace { attemptedAutomatic = true; retry() }
                return
            }
            let wakeTrigger = options.onWake && (event == .wake ||
                (discoveredLock && ProcessInfo.processInfo.systemUptime - lastWake < 3))
            let lockTrigger = options.onLock && (discoveredLock || event == .lock)
            guard wakeTrigger || lockTrigger else { return }
            // A poll can discover a missed lock, but cannot override a disabled trigger.
            guard !attemptedAutomatic, !submittedThisLock, state != .scanning, state != .submitting else { return }
            attemptedAutomatic = true
            beginScan(session: session)
        }
    }

    func retry() {
        guard modelPolicy.allowsUnlock, options.livenessEnabled, !isBusy, !submittedThisLock, scansThisLock < 3,
              case .locked(let session) = platform.screenState,
              lockedSession == session, isEnabled, vault?.isArmed == true,
              state != .scanning, state != .submitting else { return }
        beginScan(session: session)
    }

    func cancelScan() {
        attemptedAutomatic = true
        invalidateAttempt()
        refreshReadiness()
    }

    private func beginScan(session: MacUnlockSession) {
        guard modelPolicy.allowsUnlock, scansThisLock < 3, let binding = vault?.binding else { return }
        invalidateAttempt()
        scansThisLock += 1
        let token = generation
        scanner.configure(options: options)
        presenter.configure(options: options)
        state = .scanning
        logger.info("Mac unlock scan started")
        attemptTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await enrollments.identity(for: binding)
                guard valid(token, session: session, binding: binding) else { abandon(token); return }
                guard !options.showAnimation || presenter.show(activity: activity) else {
                    fail("The lock-screen animation is unavailable on this version of macOS.", retry: false, token: token)
                    return
                }
                activity.begin(reason: "Unlock Mac")
                let result = await scanner.scan(identity: identity) { [weak self] message in
                    guard let self, self.generation == token else { return }
                    self.activity.update(prompt: message)
                }
                guard valid(token, session: session, binding: binding) else { abandon(token); return }
                switch result {
                case .cancelled: abandon(token); return
                case .failed(let message): fail(message, retry: scansThisLock < 3, token: token); return
                case .verified: break
                }
                // Reload after the camera await: deletion, replacement and model changes revoke approval.
                _ = try await enrollments.identity(for: binding)
                guard valid(token, session: session, binding: binding), let vault else { abandon(token); return }
                var password = try vault.password(for: binding)
                defer { password.resetBytes(in: 0..<password.count) }
                submittedThisLock = true
                state = .submitting
                logger.info("Mac unlock face verified; requesting secure password entry")
                activity.update(prompt: "Unlocking…")
                try await platform.submit(password: password, for: session) { [weak self] in
                    self?.valid(token, session: session, binding: binding) == true
                }
                guard generation == token else { return }
                let deadline = ContinuousClock.now.advanced(by: confirmationTimeout)
                while ContinuousClock.now < deadline, generation == token, !Task.isCancelled {
                    if case .unlocked(let current) = platform.screenState, current == session {
                        finishUnlock()
                        return
                    }
                    guard case .locked(let current) = platform.screenState, current == session else { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                fail("Mac did not unlock. Enter your password, then update it in Face Check settings.", retry: false, token: token)
            } catch {
                guard generation == token else { return }
                // A manual unlock may race the final event. Only an observed unlocked session resolves success.
                if submittedThisLock, case .unlocked(let current) = platform.screenState, current == session {
                    finishUnlock()
                } else {
                    fail(error.localizedDescription, retry: !submittedThisLock && scansThisLock < 3, token: token)
                }
            }
        }
    }

    private func valid(_ token: Int, session: MacUnlockSession, binding: MacUnlockBinding) -> Bool {
        modelPolicy.allowsUnlock && options.livenessEnabled && generation == token && !Task.isCancelled && !sleeping
            && isEnabled && vault?.isArmed == true
            && vault?.binding == binding && platform.accessibilityGranted
            && platform.screenState == .locked(session)
    }

    private func invalidateAttempt() {
        generation &+= 1
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        attemptTask?.cancel()
        attemptTask = nil
        scanner.cancel()
        activity.dismiss()
        presenter.hide()
        if state == .scanning || state == .submitting || state == .unlocked { state = .ready }
    }

    private func abandon(_ token: Int) {
        guard generation == token else { return }
        invalidateAttempt()
        refreshReadiness()
    }

    private func fail(_ message: String, retry: Bool, token: Int) {
        guard generation == token, !Task.isCancelled else { return }
        scanner.cancel()
        logger.info("Mac unlock attempt failed; password submission started=\(self.submittedThisLock)")
        state = .failed(message)
        activity.finish(recognized: false, message: message, retryAvailable: retry)
        if submittedThisLock { vault?.disarm(); isAuthorized = false }
        if retry, options.autoRetry, !automaticRetryUsed, !submittedThisLock {
            automaticRetryUsed = true
            automaticRetryTask = Task { [weak self, automaticRetryDelay] in
                try? await Task.sleep(for: automaticRetryDelay)
                guard !Task.isCancelled, let self, generation == token else { return }
                self.retry()
            }
        }
    }

    private func finishUnlock() {
        generation &+= 1
        attemptTask?.cancel()
        attemptTask = nil
        scanner.cancel()
        lockedSession = nil
        attemptedAutomatic = false
        submittedThisLock = false
        scansThisLock = 0
        state = .unlocked
        vault?.recordSuccessfulUnlock()
        logger.info("Mac unlock observed for the original session")
        presenter.didUnlock()
        activity.finish(recognized: true, message: "Mac unlocked")
    }
}

/// Low-frequency state reconciliation catches missed notifications without running the camera.
@MainActor
private final class MacUnlockMonitor {
    private let callback: (MacUnlockEvent) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private lazy var spaceTrigger = MacUnlockSpaceTrigger { [weak self] in self?.callback(.space) }
    init(callback: @escaping (MacUnlockEvent) -> Void) { self.callback = callback }

    func start() {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, event) in [(NSWorkspace.willSleepNotification, MacUnlockEvent.sleep),
                              (NSWorkspace.screensDidSleepNotification, .sleep),
                              (NSWorkspace.didWakeNotification, .wake), (NSWorkspace.screensDidWakeNotification, .wake),
                              (NSWorkspace.sessionDidResignActiveNotification, .sessionChanged),
                              (NSWorkspace.sessionDidBecomeActiveNotification, .sessionChanged)] {
            observe(workspace, name: name, event: event)
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, event) in [("com.apple.screenIsLocked", MacUnlockEvent.lock),
                              ("com.apple.screenIsUnlocked", .unlock), ("com.apple.screensaver.didstop", .wake)] {
            observe(distributed, name: Notification.Name(name), event: event)
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.callback(.poll) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        spaceTrigger.stop()
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    func setSpaceEnabled(_ enabled: Bool) {
        if enabled { spaceTrigger.start() } else { spaceTrigger.stop() }
    }

    isolated deinit { stop() }

    private func observe(_ center: NotificationCenter, name: Notification.Name, event: MacUnlockEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.callback(event) }
        }
        observers.append((center, token))
    }
}
