@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import os
import VideoToolbox

protocol FaceCheckCameraCapturing: Sendable {
    var session: AVCaptureSession { get }
    var authorizationStatus: AVAuthorizationStatus { get }
    func requestAuthorization() async -> Bool
    func start(onFrame: @escaping FaceCheckCamera.FrameHandler, completion: @escaping @Sendable (Bool) -> Void)
    func stop(completion: (@Sendable () -> Void)?)
}

extension FaceCheckCameraCapturing {
    func stop() { stop(completion: nil) }
}

/// The camera for Face Check: one `AVCaptureSession` with a preview for the settings page and a
/// frame tap for the analysis pipeline.
///
/// Session work runs in order on one serial queue; frames arrive on another. A frame is handed
/// on only while the pipeline is idle, so a slow frame is dropped rather than queued and the
/// camera never builds a backlog. Nothing here touches the main thread.
final class FaceCheckCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FaceCheckCameraCapturing, @unchecked Sendable {
    /// Receives one frame at a time; the next frame is offered once it returns.
    typealias FrameHandler = @Sendable (CGImage, TimeInterval) async -> Void

    /// Read a stable reference from the lock, never a bare function value. Passing an async
    /// closure through generic inout storage can accumulate reabstraction wrappers on each
    /// read, then overflow the stack when the camera releases the callback.
    struct FrameCallbackStore: Sendable {
        final class Receiver: Sendable {
            private let callback: FrameHandler

            init(_ callback: @escaping FrameHandler) { self.callback = callback }

            func receive(_ image: CGImage, capturedAt: TimeInterval) async {
                await callback(image, capturedAt)
            }
        }

        private let receiver = OSAllocatedUnfairLock<Receiver?>(initialState: nil)

        func replace(with callback: @escaping FrameHandler) {
            let next = Receiver(callback)
            receiver.withLock { $0 = next }
        }

        func snapshot() -> Receiver? { receiver.withLock { $0 } }

        func clear() { receiver.withLock { $0 = nil } }
    }

    /// The session the preview layer draws from. Only reconfigured on `sessionQueue`.
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "Notchy.FaceCheck.Session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "Notchy.FaceCheck.Frames", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    /// Confined to `sessionQueue`.
    private var input: AVCaptureDeviceInput?
    private let isBusy = OSAllocatedUnfairLock(initialState: false)
    private let handler = FrameCallbackStore()

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    var authorizationStatus: AVAuthorizationStatus { Self.authorization }
    func requestAuthorization() async -> Bool { await Self.requestAccess() }

    /// Opens the front camera and starts delivering frames to `onFrame`. Reports whether the
    /// session is running.
    func start(onFrame: @escaping FrameHandler, completion: @escaping @Sendable (Bool) -> Void) {
        handler.replace(with: onFrame)
        sessionQueue.async { [self] in
            completion(startOnQueue())
        }
    }

    /// Stops the session and detaches the camera, so the camera light goes out.
    func stop(completion: (@Sendable () -> Void)? = nil) {
        handler.clear()
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            if let input {
                session.beginConfiguration()
                session.removeInput(input)
                session.commitConfiguration()
                self.input = nil
            }
            completion?()
        }
    }

    // MARK: Session

    private func startOnQueue() -> Bool {
        if input == nil {
            guard let device = Self.preferredCamera() else { return false }
            session.beginConfiguration()
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            if let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
            }
            if !session.outputs.contains(output) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: frameQueue)
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            // Vision uses the original camera coordinates. Only the preview is mirrored.
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            session.commitConfiguration()
        }
        guard input != nil else { return false }
        if !session.isRunning { session.startRunning() }
        return session.isRunning
    }

    /// The built-in FaceTime camera when there is one, otherwise the first front-facing or
    /// external camera. Desk View is skipped: it never shows a face straight on.
    private static func preferredCamera() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        return devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? devices.first { $0.position == .front }
            ?? devices.first
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Stamp delivery before conversion/model work. Analysis completion is not the time
        // the eyelids or head moved, and must not define the challenge's temporal evidence.
        let capturedAt = ProcessInfo.processInfo.systemUptime
        guard let receiver = handler.snapshot() else { return }
        let claimed = isBusy.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard claimed else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isBusy.withLock { $0 = false }
            return
        }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else {
            isBusy.withLock { $0 = false }
            return
        }
        let isBusy = isBusy
        Task.detached(priority: .userInitiated) {
            await receiver.receive(image, capturedAt: capturedAt)
            isBusy.withLock { $0 = false }
        }
    }
}
