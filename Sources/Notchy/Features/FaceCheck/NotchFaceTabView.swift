import SwiftUI

/// The Face Check tab in the open island: a live camera view with the face outlined, enrolment
/// with its pose grid, and a test scan with its result. The camera runs only while this tab is
/// on screen.
struct NotchFaceTabView: View {
    let model: NotchViewModel
    @ObservedObject private var controller: FaceCheckController
    @State private var previewID = UUID()

    init(model: NotchViewModel, controller: FaceCheckController = .shared) {
        self.model = model
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            cameraView
            VStack(alignment: .leading, spacing: 7) {
                header
                actions
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if controller.activity == .enrolling {
                FaceEnrollmentGrid(counts: controller.poseCounts, samplesPerPose: controller.samplesPerPose, cell: 12.5)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            controller.loadIdentities()
            controller.retainPreview(previewID, start: true)
        }
        .onDisappear {
            controller.releasePreview(previewID)
            model.releaseHold(reason: "faceEnrollment")
        }
        .onChange(of: controller.activity) { _, activity in
            if activity == .enrolling || activity == .saving { model.holdOpen(reason: "faceEnrollment") }
            else { model.releaseHold(reason: "faceEnrollment") }
        }
    }

    // MARK: Parts

    private var cameraView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if controller.cameraState == .on || controller.cameraState == .starting {
                    FaceCheckPreview(session: controller.camera.session, faceBounds: controller.face?.bounds)
                } else {
                    Color.white.opacity(0.06).overlay {
                        Image(systemName: controller.cameraState == .denied ? "video.slash" : "faceid")
                            .font(.system(size: 21))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 136, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let chip = controller.chip, controller.cameraState == .on {
                Image(decorative: chip, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 31, height: 31)
                    .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
                    .padding(4)
                    .help("What the face model sees")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Face Check")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(statusLine)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
            if let distance = controller.liveDistance {
                let limit = controller.preset.maximumDistance
                Text("Distance \(String(format: "%.2f", distance)) / \(String(format: "%.2f", limit))")
                    .font(.system(size: 7.5).monospacedDigit())
                    .foregroundStyle(distance <= limit ? .green : .orange)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch controller.activity {
        case .enrolling:
            HStack(spacing: 5.5) {
                IslandActionButton(title: "Finish now", systemImage: "checkmark", prominent: true) { controller.finishEnrolment() }
                    .disabled(!controller.canFinishEnrolmentEarly)
                IslandActionButton(title: "Cancel", systemImage: "xmark") { controller.cancelEnrolment() }
            }
        case .testing:
            IslandActionButton(title: "Cancel check", systemImage: "xmark") { controller.cancelVerification() }
        case .saving:
            Text("Saving your face…").font(.system(size: 8.5)).foregroundStyle(.secondary)
        case .watching:
            HStack(spacing: 5.5) {
                if controller.identities.isEmpty {
                    IslandActionButton(title: "Scan my face", systemImage: "faceid", prominent: true) {
                        controller.startEnrolment(name: "Me")
                    }
                } else {
                    IslandActionButton(title: "Check now", systemImage: "faceid", prominent: true) { controller.startTest() }
                    IslandActionButton(title: "Scan again", systemImage: "arrow.clockwise") {
                        controller.startEnrolment(name: "Me")
                    }
                }
                if controller.cameraState == .denied {
                    IslandActionButton(title: "Allow camera", systemImage: "video") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if let outcome = controller.testOutcome {
                HStack(spacing: 4) {
                    Image(systemName: outcome.matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(outcome.matched ? .green : .orange)
                    Text(outcome.matched ? "It's \(outcome.name ?? "you")" : "Not recognized")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 8.5, weight: .medium))
            }
        }
    }

    private var statusLine: String {
        switch controller.cameraState {
        case .denied: return "Notchy needs camera access."
        case .unavailable: return "No camera available."
        case .starting: return "Starting the camera…"
        case .off: return controller.status.isEmpty ? "Camera off" : controller.status
        case .on:
            if controller.activity == .watching, controller.identities.isEmpty, controller.face != nil {
                return "Ready to scan your face."
            }
            return controller.status.isEmpty ? "Looking for a face…" : controller.status
        }
    }
}

/// A compact capsule button that fits the island's dark style.
private struct IslandActionButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, 8.5)
                .padding(.vertical, 4)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

/// The nine enrolment poses as a 3×3 grid, laid out as the head moves in the mirrored preview.
struct FaceEnrollmentGrid: View {
    let counts: [FaceEnrollmentPose: Int]
    let samplesPerPose: Int
    let cell: CGFloat

    static let rows: [[FaceEnrollmentPose]] = [
        [.upRight, .up, .upLeft],
        [.right, .centre, .left],
        [.downRight, .down, .downLeft],
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(Self.rows[row], id: \.self) { pose in
                        let count = counts[pose] ?? 0
                        RoundedRectangle(cornerRadius: cell / 5)
                            .fill(count >= samplesPerPose ? Color.green : (count > 0 ? Color.green.opacity(0.45) : Color.gray.opacity(0.3)))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counts.values.reduce(0, +)) of \(FaceEnrollmentPose.allCases.count * samplesPerPose) samples captured")
    }
}
