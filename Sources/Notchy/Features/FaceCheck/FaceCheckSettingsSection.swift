@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Face Check's settings: a live camera view with the face box and the aligned chip, enrolment,
/// a test scan with its distance, the match strictness, and the saved faces.
struct FaceCheckSettingsSection: View {
    @ObservedObject private var controller: FaceCheckController
    @State private var enrolName = "Me"
    @State private var confirmDeleteAll = false
    @State private var previewID = UUID()

    init(controller: FaceCheckController = .shared) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        Group {
            Section {
                Text("Face Check recognises your face with the camera to reveal hidden clipboard items and confirm actions. You can also set up Mac Face Unlock below. Face descriptors stay encrypted on this Mac; camera pictures are never saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Camera") {
                cameraView
                HStack {
                    Text(cameraStatus).foregroundStyle(.secondary)
                    Spacer()
                    if controller.cameraState == .on || controller.cameraState == .starting {
                        Button("Stop camera") { controller.stopCamera() }
                    } else {
                        Button("Start camera") { controller.startCamera() }
                    }
                }
                if controller.cameraState == .denied {
                    Button("Open Camera privacy settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if let problem = controller.problem {
                    Text(problem).foregroundStyle(.red)
                }
            }

            Section("Enrol") {
                if controller.activity == .enrolling {
                    enrolmentProgress
                } else {
                    HStack {
                        TextField("Name", text: $enrolName)
                            .frame(maxWidth: 200)
                        Button("Enrol my face") { controller.startEnrolment(name: enrolName) }
                            .disabled(controller.activity != .watching)
                    }
                    Text("Follow the circular guide at the top of your screen. Blink when asked, then turn your head slowly until the ring fills. Your face saves automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Test") {
                HStack {
                    Button(controller.activity == .testing ? "Scanning…" : "Test Face Check") { controller.startTest() }
                        .disabled(controller.activity != .watching || controller.identities.isEmpty)
                    Spacer()
                    if let outcome = controller.testOutcome { outcomeLabel(outcome) }
                }
                Picker("Match strictness", selection: $controller.preset) {
                    ForEach(FaceMatchPreset.allCases, id: \.self) { preset in
                        Text("\(preset.title) (\(String(format: "%.2f", preset.maximumDistance)))").tag(preset)
                    }
                }
                .disabled(controller.usesCalibratedThreshold)
                Text("Every check needs a face match, a blink, and a requested head turn. Lower distance means a stricter match; it never turns off the live check. Camera checks cannot guarantee protection against every photo or replayed video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MacUnlockSettingsSection(controller: .shared, faces: controller)

            Section("Saved faces") {
                if let storeProblem = controller.storeProblem {
                    Text(storeProblem).foregroundStyle(.red)
                }
                if controller.identities.isEmpty {
                    Text("No faces enrolled yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(controller.identities) { identity in
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text(identity.name)
                            Text("\(identity.capturedViewCount) captures").foregroundStyle(.secondary)
                            if !identity.supportsPassiveUnlock {
                                Text("Rescan for Face Unlock").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { controller.deleteIdentity(identity) }
                        }
                    }
                }
                Button("Delete all face data…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(controller.identities.isEmpty && controller.storeProblem == nil)
            }
        }
        .onAppear {
            controller.loadIdentities()
            controller.retainPreview(previewID, start: false)
        }
        .onDisappear { controller.releasePreview(previewID) }
        .confirmationDialog("Delete all face data?", isPresented: $confirmDeleteAll) {
            Button("Delete", role: .destructive) { controller.deleteAllFaceData() }
        } message: {
            Text("Every enrolled face and its key are removed from this Mac.")
        }
    }

    // MARK: Camera

    private var cameraView: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if controller.cameraState == .on || controller.cameraState == .starting {
                    FaceCheckPreview(session: controller.camera.session, faceBounds: controller.face?.bounds)
                } else {
                    Color.black.overlay {
                        Image(systemName: "video.slash").font(.title).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let chip = controller.chip {
                        Image(decorative: chip, scale: 1).resizable().interpolation(.high)
                    } else {
                        Color.black.opacity(0.4)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("What the model sees").font(.caption2).foregroundStyle(.secondary)
                readouts
            }
        }
        .padding(.vertical, 4)
    }

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let face = controller.face {
                Text("Turn \(Self.degrees(face.yaw))  Tilt \(Self.degrees(face.pitch))")
                Text("Quality \(String(format: "%.2f", face.quality))")
            }
            if let distance = controller.liveDistance {
                let limit = controller.matchingDistanceLimit
                Text("Distance \(String(format: "%.2f", distance)) / \(String(format: "%.2f", limit))")
                    .foregroundStyle(distance <= limit ? .green : .orange)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var cameraStatus: String {
        switch controller.cameraState {
        case .off: "Camera off"
        case .starting: "Starting the camera…"
        case .on: controller.status.isEmpty ? "Camera on" : controller.status
        case .denied: "Notchy isn't allowed to use the camera."
        case .unavailable: "No camera available."
        }
    }

    // MARK: Enrolment

    private var enrolmentProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Follow the guide at the top of your screen.")
            Text("\(capturedTotal) of \(FaceEnrollmentPose.allCases.count * controller.samplesPerPose) samples")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel scan") { controller.cancelEnrolment() }
        }
    }

    private var capturedTotal: Int { controller.poseCounts.values.reduce(0, +) }

    // MARK: Test

    private func outcomeLabel(_ outcome: FaceCheckController.TestOutcome) -> some View {
        HStack(spacing: 6) {
            Image(systemName: outcome.matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(outcome.matched ? .green : .orange)
            Text(outcome.matched ? "It's \(outcome.name ?? "you")" : "Not recognized")
            if let distance = outcome.distance {
                Text("distance \(String(format: "%.2f", distance)) / \(String(format: "%.2f", outcome.limit))")
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private static func degrees(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%+.0f°", value)
    }
}

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
