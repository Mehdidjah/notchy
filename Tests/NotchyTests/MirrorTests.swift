import AVFoundation
import Foundation
import Testing
@testable import Notchy

@MainActor
private final class FakeMirrorBackend: MirrorCameraBackend {
    var status: MirrorCameraAuthorization = .authorized
    var cameras = [MirrorCameraDevice(id: "facetime", name: "FaceTime HD Camera", isFrontFacing: true)]
    var grantsAccess = true

    private(set) var calls: [String] = []
    private var pendingStarts: [@MainActor @Sendable (Bool) -> Void] = []
    private var pendingAccess: [@MainActor @Sendable (Bool) -> Void] = []

    var captureSession: AVCaptureSession? { nil }

    func authorizationStatus() -> MirrorCameraAuthorization { status }

    func requestAccess(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        calls.append("requestAccess")
        pendingAccess.append(completion)
    }

    func listCameras(_ completion: @escaping @MainActor @Sendable ([MirrorCameraDevice]) -> Void) {
        completion(cameras)
    }

    func startSession(savedCameraID: String, _ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        calls.append("start:\(savedCameraID)")
        pendingStarts.append(completion)
    }

    func stopSession() {
        calls.append("stop")
    }

    /// Delivers the oldest outstanding start result.
    func finishStart(_ running: Bool = true) {
        guard !pendingStarts.isEmpty else { return }
        pendingStarts.removeFirst()(running)
    }

    func answerAccess() {
        guard !pendingAccess.isEmpty else { return }
        status = grantsAccess ? .authorized : .denied
        pendingAccess.removeFirst()(grantsAccess)
    }
}

@MainActor
struct MirrorTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "MirrorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeController(enabled: Bool = true) -> (WebcamController, FakeMirrorBackend, MirrorSettings) {
        let settings = MirrorSettings(defaults: makeDefaults())
        settings.isEnabled = enabled
        let backend = FakeMirrorBackend()
        let controller = WebcamController(settings: settings, backend: backend)
        controller.presentAccessDenied = { _ in }
        controller.refreshCameras()
        return (controller, backend, settings)
    }

    // MARK: Settings and camera choice

    @Test
    func settingsUseAtollDefaultsAndPersist() {
        let defaults = makeDefaults()
        let settings = MirrorSettings(defaults: defaults)
        #expect(settings.isEnabled == false)
        #expect(settings.shape == .rectangle)
        #expect(settings.cameraID.isEmpty)

        settings.isEnabled = true
        settings.shape = .circle
        settings.cameraID = "usb-cam"
        let reloaded = MirrorSettings(defaults: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.shape == .circle)
        #expect(reloaded.cameraID == "usb-cam")
    }

    @Test
    func shapesUseAtollCornerRadii() {
        #expect(MirrorShape.rectangle.previewCornerRadius == 13)
        #expect(MirrorShape.rectangle.placeholderCornerRadius == 12)
        #expect(MirrorShape.circle.previewCornerRadius == 100)
        #expect(MirrorShape.rectangle.displayName == "Square")
        #expect(MirrorShape.circle.displayName == "Circle")
    }

    @Test
    func preferredCameraIsSavedChoiceThenFrontThenFirst() {
        let usb = MirrorCameraDevice(id: "usb", name: "USB", isFrontFacing: false)
        let front = MirrorCameraDevice(id: "front", name: "FaceTime", isFrontFacing: true)
        let desk = MirrorCameraDevice(id: "desk", name: "Desk View", isFrontFacing: false)

        #expect(MirrorCameraDevice.preferred(among: [usb, front, desk], savedID: "desk") == desk)
        #expect(MirrorCameraDevice.preferred(among: [usb, front, desk], savedID: "") == front)
        #expect(MirrorCameraDevice.preferred(among: [usb, front, desk], savedID: "gone") == front)
        #expect(MirrorCameraDevice.preferred(among: [usb, desk], savedID: "") == usb)
        #expect(MirrorCameraDevice.preferred(among: [], savedID: "usb") == nil)
    }

    // MARK: Session lifecycle

    @Test
    func cameraRunsOnlyWhileRequestedAndOnScreen() {
        let (controller, backend, _) = makeController()
        let slot = UUID()

        controller.togglePreview()
        #expect(controller.isPreviewRequested)
        #expect(backend.calls.isEmpty, "nothing on screen yet")

        controller.setMirror(slot, visible: true)
        #expect(backend.calls == ["start:"])
        #expect(controller.isSessionRunning == false)
        backend.finishStart()
        #expect(controller.isSessionRunning)

        controller.setMirror(slot, visible: false)
        #expect(backend.calls == ["start:", "stop"])
        #expect(controller.isSessionRunning == false)
        #expect(controller.isPreviewRequested == false, "the next open starts from the placeholder")
    }

    @Test
    func showingTheMirrorDoesNotStartTheCameraUntilClicked() {
        let (controller, backend, _) = makeController()
        controller.setMirror(UUID(), visible: true)
        #expect(backend.calls.isEmpty)
        controller.togglePreview()
        #expect(backend.calls == ["start:"])
        backend.finishStart()
        controller.togglePreview()
        #expect(backend.calls == ["start:", "stop"])
        #expect(controller.isSessionRunning == false)
    }

    @Test
    func lateStartResultCannotReviveAStoppedSession() {
        let (controller, backend, _) = makeController()
        let slot = UUID()
        controller.setMirror(slot, visible: true)
        controller.togglePreview()
        controller.togglePreview()
        #expect(backend.calls == ["start:", "stop"])

        backend.finishStart(true)
        #expect(controller.isSessionRunning == false)
    }

    @Test
    func failedStartDropsTheRequest() {
        let (controller, backend, _) = makeController()
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview()
        backend.finishStart(false)
        #expect(controller.isSessionRunning == false)
        #expect(controller.isPreviewRequested == false)
    }

    @Test
    func firstClickOnlyAsksForAccessAndTheNextClickStartsTheCamera() {
        let (controller, backend, _) = makeController()
        backend.status = .notDetermined
        controller.refreshAuthorization()
        controller.setMirror(UUID(), visible: true)

        controller.togglePreview()
        #expect(backend.calls == ["requestAccess"])
        controller.togglePreview()
        #expect(backend.calls == ["requestAccess"], "a second click while asking is ignored")

        backend.answerAccess()
        #expect(controller.authorization == .authorized)
        #expect(controller.isPreviewRequested == false, "Atoll waits for another click after the grant")
        #expect(backend.calls == ["requestAccess"])

        controller.togglePreview()
        #expect(backend.calls == ["requestAccess", "start:"])
    }

    @Test
    func grantArrivingAfterTheIslandClosedDoesNotStartTheCameraOnTheNextOpen() {
        let (controller, backend, _) = makeController()
        backend.status = .notDetermined
        controller.refreshAuthorization()
        let slot = UUID()
        controller.setMirror(slot, visible: true)
        controller.togglePreview()
        controller.setMirror(slot, visible: false)

        backend.answerAccess()
        controller.setMirror(slot, visible: true)
        #expect(backend.calls == ["requestAccess"])
    }

    @Test
    func deniedAccessExplainsInsteadOfStarting() {
        let (controller, backend, _) = makeController()
        backend.status = .denied
        var sources: [MirrorToggleSource] = []
        controller.presentAccessDenied = { sources.append($0) }
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview(from: .mirror)
        controller.togglePreview(from: .headerButton)
        #expect(sources == [.mirror, .headerButton], "each source gets Atoll's own alert")
        #expect(backend.calls.isEmpty)
        #expect(controller.authorization.isBlocked)
    }

    @Test
    func noCameraMeansNoSession() {
        let (controller, backend, _) = makeController()
        backend.cameras = []
        controller.refreshCameras()
        #expect(controller.cameraAvailable == false)
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview()
        #expect(backend.calls.isEmpty)
    }

    @Test
    func turningTheMirrorOffStopsTheCamera() {
        let (controller, backend, settings) = makeController()
        controller.start()
        defer { controller.stop() }
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview()
        backend.finishStart()

        settings.isEnabled = false
        #expect(backend.calls.last == "stop")
        #expect(controller.isSessionRunning == false)
    }

    @Test
    func requestMadeOffScreenIsDroppedWhenTheIslandCloses() {
        let (controller, backend, _) = makeController()
        controller.togglePreview()
        #expect(controller.isPreviewRequested)
        controller.headerDidDisappear()
        #expect(controller.isPreviewRequested == false)

        controller.setMirror(UUID(), visible: true)
        #expect(backend.calls.isEmpty)
    }

    @Test
    func unpluggingACameraStopsTheRunningPreview() {
        let (controller, backend, _) = makeController()
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview()
        backend.finishStart()
        #expect(controller.isSessionRunning)

        controller.cameraWasDisconnected()
        #expect(backend.calls == ["start:", "stop"])
        #expect(controller.isSessionRunning == false)
        #expect(controller.isPreviewRequested == false)
        #expect(controller.cameraAvailable, "the remaining camera is still listed")
    }

    @Test
    func changingCameraReopensARunningSession() {
        let (controller, backend, settings) = makeController()
        controller.setMirror(UUID(), visible: true)
        controller.togglePreview()
        backend.finishStart()

        settings.cameraID = "usb"
        controller.cameraSelectionDidChange()
        #expect(backend.calls == ["start:", "stop", "start:usb"])
    }

    @Test
    func stoppingTheFeatureRemovesTheMirrorFromHome() {
        let layout = HomeLayoutState.shared
        let previous = layout.showsMirror
        defer { layout.showsMirror = previous }

        MirrorFeature.stop()
        #expect(layout.showsMirror == false)
    }
}
