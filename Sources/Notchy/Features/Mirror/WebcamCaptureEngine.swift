@preconcurrency import AVFoundation
import Foundation

/// A camera the mirror can use.
struct MirrorCameraDevice: Identifiable, Hashable, Sendable {
    /// `AVCaptureDevice.uniqueID`.
    let id: String
    let name: String
    /// The built-in FaceTime camera, or any camera that reports the front position.
    let isFrontFacing: Bool

    /// The camera to open: the saved choice when it is still connected, otherwise the
    /// front-facing camera, otherwise the first one found.
    static func preferred(among devices: [MirrorCameraDevice], savedID: String) -> MirrorCameraDevice? {
        if !savedID.isEmpty, let saved = devices.first(where: { $0.id == savedID }) {
            return saved
        }
        return devices.first(where: \.isFrontFacing) ?? devices.first
    }
}

/// Owns the `AVCaptureSession` and does all session work on one serial queue, so calls made
/// from the main actor run in the order they were made. Methods return at once; completions
/// run on the session queue.
final class WebcamCaptureEngine: @unchecked Sendable {
    /// The session the preview layers draw from. Only reconfigured on `queue`.
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "Notchy.Mirror.CaptureSession", qos: .userInitiated)
    /// Confined to `queue`.
    private var currentInput: AVCaptureDeviceInput?

    static let deviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera
    ]

    func listCameras(_ completion: @escaping @Sendable ([MirrorCameraDevice]) -> Void) {
        queue.async {
            completion(Self.discover().map(Self.describe))
        }
    }

    /// Opens the preferred camera, switching input if a different one is selected now, and
    /// starts the session. Reports whether the session is running.
    func start(savedCameraID: String, _ completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            completion(startOnQueue(savedCameraID: savedCameraID))
        }
    }

    /// Stops the session and detaches the camera so its indicator light goes out.
    func stop(_ completion: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            stopOnQueue()
            completion?()
        }
    }

    // MARK: Queue-confined work

    private func startOnQueue(savedCameraID: String) -> Bool {
        let devices = Self.discover()
        let choice = MirrorCameraDevice.preferred(among: devices.map(Self.describe), savedID: savedCameraID)
        guard let choice, let device = devices.first(where: { $0.uniqueID == choice.id }) else {
            stopOnQueue()
            return false
        }

        if currentInput?.device.uniqueID != device.uniqueID {
            session.beginConfiguration()
            if let currentInput { session.removeInput(currentInput) }
            currentInput = nil
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    currentInput = input
                }
            } catch {
                currentInput = nil
            }
            session.commitConfiguration()
        }

        guard currentInput != nil else { return false }
        if !session.isRunning { session.startRunning() }
        return session.isRunning
    }

    private func stopOnQueue() {
        if session.isRunning { session.stopRunning() }
        guard let currentInput else { return }
        session.beginConfiguration()
        session.removeInput(currentInput)
        session.commitConfiguration()
        self.currentInput = nil
    }

    private static func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private static func describe(_ device: AVCaptureDevice) -> MirrorCameraDevice {
        MirrorCameraDevice(
            id: device.uniqueID,
            name: device.localizedName,
            isFrontFacing: device.position == .front || device.deviceType == .builtInWideAngleCamera
        )
    }
}
