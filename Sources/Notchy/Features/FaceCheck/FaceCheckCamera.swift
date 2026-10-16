@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import os
import VideoToolbox

/// The camera for Face Check: one `AVCaptureSession` with a preview for the settings page and a
/// frame tap for the analysis pipeline.
///
/// Session work runs in order on one serial queue; frames arrive on another. A frame is handed
/// on only while the pipeline is idle, so a slow frame is dropped rather than queued and the
/// camera never builds a backlog. Nothing here touches the main thread.
final class FaceCheckCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Receives one frame at a time; the next frame is offered once it returns.
    typealias FrameHandler = @Sendable (CGImage) async -> Void

    /// The session the preview layer draws from. Only reconfigured on `sessionQueue`.
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "Notchy.FaceCheck.Session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "Notchy.FaceCheck.Frames", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    /// Confined to `sessionQueue`.
    private var input: AVCaptureDeviceInput?
    private let isBusy = OSAllocatedUnfairLock(initialState: false)
    private let handler = OSAllocatedUnfairLock<FrameHandler?>(initialState: nil)

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Opens the front camera and starts delivering frames to `onFrame`. Reports whether the
    /// session is running.
    func start(onFrame: @escaping FrameHandler, completion: @escaping @Sendable (Bool) -> Void) {
        handler.withLock { $0 = onFrame }
        sessionQueue.async { [self] in
            completion(startOnQueue())
        }
    }

    /// Stops the session and detaches the camera, so the camera light goes out.
    func stop(completion: (@Sendable () -> Void)? = nil) {
        handler.withLock { $0 = nil }
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
        guard let onFrame = handler.withLock({ $0 }) else { return }
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
            await onFrame(image)
            isBusy.withLock { $0 = false }
        }
    }
}
