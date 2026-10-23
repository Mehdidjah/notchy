@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// The camera preview, mirrored like a mirror, with the detected face outlined.
struct FaceCheckPreview: NSViewRepresentable {
    let session: AVCaptureSession
    /// Normalised to the camera frame, origin at the top left.
    let faceBounds: CGRect?

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.showFace(faceBounds)
    }

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer
        private let boxLayer = CAShapeLayer()
        private var faceBounds: CGRect?

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            layer = CALayer()
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
            boxLayer.fillColor = nil
            boxLayer.strokeColor = NSColor.systemGreen.cgColor
            boxLayer.lineWidth = 2
            previewLayer.addSublayer(boxLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // frame is undefined for a transformed layer; place its untransformed bounds first.
            previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            previewLayer.setAffineTransform(FacePreviewGeometry.mirrorTransform)
            boxLayer.frame = previewLayer.bounds
            CATransaction.commit()
            showFace(faceBounds)
        }

        func showFace(_ bounds: CGRect?) {
            faceBounds = bounds
            disableConnectionMirroring()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let bounds {
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: bounds)
                boxLayer.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
                boxLayer.isHidden = false
            } else {
                boxLayer.isHidden = true
            }
            CATransaction.commit()
        }

        private func disableConnectionMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
            if connection.isVideoMirrored { connection.isVideoMirrored = false }
        }
    }
}

enum FacePreviewGeometry {
    static let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
    static func mirrored(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + bounds.maxX - point.x, y: point.y)
    }
}
