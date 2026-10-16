@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Draws a capture session through its own `AVCaptureVideoPreviewLayer`, flipped horizontally
/// like a mirror, filling the frame and rounded to `cornerRadius`. The flip and the rounding are
/// done on the layers, where they hold for an AppKit-hosted view. Clicks pass through to the
/// SwiftUI view underneath.
struct MirrorCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> MirrorPreviewHostView {
        let view = MirrorPreviewHostView(session: session)
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: MirrorPreviewHostView, context: Context) {
        view.attach(session)
        view.cornerRadius = cornerRadius
    }
}

final class MirrorPreviewHostView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    /// Clamped to half the shorter side, so a large radius draws a circle.
    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            needsLayout = true
        }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        // Mirror image, as a mirror app shows it.
        previewLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
        // The connection is rebuilt each time the camera input is added; pin its mirroring
        // then. Selector observers are removed automatically when the view goes away.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStartRunning(_:)),
            name: AVCaptureSession.didStartRunningNotification,
            object: session
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.cornerRadius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        CATransaction.commit()
        lockConnectionMirroring()
    }

    /// The layer transform does the mirroring, so the connection must not mirror as well
    /// (AVFoundation may do so on its own for a front camera).
    private func lockConnectionMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoMirrored {
            connection.isVideoMirrored = false
        }
    }

    /// Posted on the session queue.
    @objc nonisolated private func sessionDidStartRunning(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.lockConnectionMirroring() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func attach(_ session: AVCaptureSession) {
        guard previewLayer.session !== session else { return }
        if let old = previewLayer.session {
            NotificationCenter.default.removeObserver(self, name: AVCaptureSession.didStartRunningNotification, object: old)
        }
        previewLayer.session = session
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStartRunning(_:)),
            name: AVCaptureSession.didStartRunningNotification,
            object: session
        )
        lockConnectionMirroring()
    }
}
