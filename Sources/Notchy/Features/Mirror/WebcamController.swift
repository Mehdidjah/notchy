import AppKit
@preconcurrency import AVFoundation
import Combine
import Foundation

/// Camera permission as the mirror sees it.
enum MirrorCameraAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    var isBlocked: Bool { self == .denied || self == .restricted }
}

/// Where a camera toggle came from. Atoll explains a refused permission differently for a
/// click on the mirror tile (Open Settings / Cancel) and for the header button (OK only).
enum MirrorToggleSource: Sendable, Equatable {
    case mirror
    case headerButton
}

/// What the mirror needs from the camera stack. The live version wraps AVFoundation; tests
/// substitute a fake. Calls are ordered: a stop made after a start always lands after it.
@MainActor
protocol MirrorCameraBackend: AnyObject {
    /// The session preview layers attach to, if there is a real one.
    var captureSession: AVCaptureSession? { get }
    func authorizationStatus() -> MirrorCameraAuthorization
    func requestAccess(_ completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func listCameras(_ completion: @escaping @MainActor @Sendable ([MirrorCameraDevice]) -> Void)
    func startSession(savedCameraID: String, _ completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func stopSession()
}

/// AVFoundation camera access for the mirror.
@MainActor
final class AVFoundationMirrorBackend: MirrorCameraBackend {
    let engine = WebcamCaptureEngine()

    var captureSession: AVCaptureSession? { engine.session }

    func authorizationStatus() -> MirrorCameraAuthorization {
        MirrorCameraAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    func listCameras(_ completion: @escaping @MainActor @Sendable ([MirrorCameraDevice]) -> Void) {
        engine.listCameras { devices in
            Task { @MainActor in completion(devices) }
        }
    }

    func startSession(savedCameraID: String, _ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        engine.start(savedCameraID: savedCameraID) { running in
            Task { @MainActor in completion(running) }
        }
    }

    func stopSession() {
        engine.stop()
    }
}

/// Runs the camera mirror. The camera is on only while all of these hold: the user asked for
/// the live preview (a click on the mirror or the header button), a mirror is on screen in the
/// open island, access is granted, a camera is connected and the feature is on. When the last
/// mirror leaves the screen the session stops and the request is forgotten, so the next open
/// shows the "Mirror" placeholder again, as in Atoll.
@MainActor
final class WebcamController: ObservableObject {
    static let shared = WebcamController()

    @Published private(set) var authorization: MirrorCameraAuthorization
    @Published private(set) var cameraAvailable = false
    @Published private(set) var availableCameras: [MirrorCameraDevice] = []
    /// True once the session reports frames are flowing; drives the live preview's visibility.
    @Published private(set) var isSessionRunning = false
    /// The user wants the live preview rather than the placeholder.
    @Published private(set) var isPreviewRequested = false

    let settings: MirrorSettings
    let backend: any MirrorCameraBackend
    /// Explains a refused permission; the default shows Atoll's alert for the source of the
    /// click. Tests replace it.
    var presentAccessDenied: @MainActor (MirrorToggleSource) -> Void = WebcamController.presentAccessAlert

    private var visibleSlots: Set<UUID> = []
    /// What was last asked of the backend.
    private var sessionTargetRunning = false
    /// Bumped on every start or stop so a late start result cannot undo a newer stop.
    private var generation = 0
    private var isRequestingAuthorization = false
    private var observers: [any NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: MirrorSettings = .shared, backend: any MirrorCameraBackend = AVFoundationMirrorBackend()) {
        self.settings = settings
        self.backend = backend
        authorization = backend.authorizationStatus()
    }

    var isMirrorOnScreen: Bool { !visibleSlots.isEmpty }

    /// Whether the camera should be running right now.
    var shouldRun: Bool {
        settings.isEnabled
            && isPreviewRequested
            && isMirrorOnScreen
            && authorization == .authorized
            && cameraAvailable
    }

    // MARK: Lifecycle

    func start() {
        guard observers.isEmpty else { return }
        authorization = backend.authorizationStatus()
        refreshCameras()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCameras() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameraWasDisconnected() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: backend.captureSession,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionDidFail() }
        })
        // Permission can change in System Settings while the app runs.
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAuthorization() }
        })

        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                // Dropping the request is enough for `shouldRun` to turn false.
                self.isPreviewRequested = false
                self.reconcile()
            }
            .store(in: &subscriptions)
        settings.$cameraID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.cameraSelectionDidChange() }
            }
            .store(in: &subscriptions)
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        subscriptions.removeAll()
        isPreviewRequested = false
        visibleSlots.removeAll()
        reconcile()
    }

    // MARK: User actions

    /// A click on the mirror or the header button: asks for access the first time, explains a
    /// denial, and otherwise turns the live preview on or off. As in Atoll, granting access
    /// does not start the camera by itself; the next click does.
    func togglePreview(from source: MirrorToggleSource = .mirror) {
        guard !isRequestingAuthorization else { return }
        authorization = backend.authorizationStatus()
        switch authorization {
        case .authorized:
            if isPreviewRequested {
                isPreviewRequested = false
            } else if cameraAvailable {
                isPreviewRequested = true
            } else {
                refreshCameras()
            }
            reconcile()
        case .denied, .restricted:
            presentAccessDenied(source)
        case .notDetermined:
            isRequestingAuthorization = true
            backend.requestAccess { [weak self] granted in
                guard let self else { return }
                self.isRequestingAuthorization = false
                self.authorization = granted ? .authorized : .denied
                guard granted else { return }
                self.refreshCameras()
            }
        }
    }

    // MARK: Visibility

    /// A mirror view reports whether it is on screen in the open island.
    func setMirror(_ id: UUID, visible: Bool) {
        let wasOnScreen = isMirrorOnScreen
        if visible {
            visibleSlots.insert(id)
            // Permission may have changed in System Settings; keep the caption honest.
            if !wasOnScreen { refreshAuthorization() }
        } else {
            visibleSlots.remove(id)
        }
        if wasOnScreen, !isMirrorOnScreen {
            // Atoll stops the camera when the mirror leaves the screen; the next open starts
            // from the placeholder.
            isPreviewRequested = false
        }
        reconcile()
    }

    /// The header button left the screen (the island closed). A request made while no mirror
    /// was visible is dropped so it cannot start the camera on a later open.
    func headerDidDisappear() {
        guard !isMirrorOnScreen, isPreviewRequested else { return }
        isPreviewRequested = false
        reconcile()
    }

    // MARK: Devices and permission

    func refreshCameras() {
        backend.listCameras { [weak self] devices in
            guard let self else { return }
            if self.availableCameras != devices { self.availableCameras = devices }
            let available = !devices.isEmpty
            if self.cameraAvailable != available { self.cameraAvailable = available }
            self.reconcile()
        }
    }

    func refreshAuthorization() {
        let status = backend.authorizationStatus()
        guard status != authorization else { return }
        authorization = status
        reconcile()
    }

    /// Atoll stops a running preview whenever a camera is unplugged, then re-lists cameras;
    /// the placeholder comes back and a click starts the camera again.
    func cameraWasDisconnected() {
        if isPreviewRequested {
            isPreviewRequested = false
            reconcile()
        }
        refreshCameras()
    }

    /// The saved camera changed: a running session reopens on the new one.
    func cameraSelectionDidChange() {
        guard sessionTargetRunning else { return }
        backend.stopSession()
        sessionTargetRunning = false
        isSessionRunning = false
        reconcile()
    }

    // MARK: Session

    private func sessionDidFail() {
        guard sessionTargetRunning else { return }
        isPreviewRequested = false
        reconcile()
        refreshCameras()
    }

    /// Starts or stops the session to match `shouldRun`.
    func reconcile() {
        let wantsRunning = shouldRun
        guard wantsRunning != sessionTargetRunning else { return }
        sessionTargetRunning = wantsRunning
        generation &+= 1
        let requestGeneration = generation
        if wantsRunning {
            backend.startSession(savedCameraID: settings.cameraID) { [weak self] running in
                guard let self, requestGeneration == self.generation else { return }
                self.isSessionRunning = running
                if !running {
                    self.sessionTargetRunning = false
                    self.isPreviewRequested = false
                }
            }
        } else {
            isSessionRunning = false
            backend.stopSession()
        }
    }

    /// Atoll's two alerts: the mirror tile offers Open Settings / Cancel, the header button
    /// only an OK. Focus goes back to the app the user was in afterwards.
    static func presentAccessAlert(for source: MirrorToggleSource) {
        // Let the click finish before the modal alert takes over the main thread.
        Task { @MainActor in
            let wasActive = NSApp.isActive
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Camera Access Required"
            switch source {
            case .mirror:
                alert.informativeText = "Please allow camera access in System Settings to use the mirror feature."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    openCameraPrivacySettings()
                }
            case .headerButton:
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            if !wasActive { NSApp.deactivate() }
        }
    }

    static func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
