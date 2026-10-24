import SwiftUI

/// Enrollment owns the camera in its dedicated notch surface. Opening this dashboard
/// only reads readiness; it cannot start an in-app check or a camera preview.
struct NotchFaceTabView: View {
    let model: NotchViewModel
    @ObservedObject private var controller: FaceCheckController
    @ObservedObject private var unlock: MacUnlockController

    init(model: NotchViewModel, controller: FaceCheckController = .shared,
         unlock: MacUnlockController = .shared) {
        self.model = model
        _controller = ObservedObject(wrappedValue: controller)
        _unlock = ObservedObject(wrappedValue: unlock)
    }

    var body: some View {
        HStack(spacing: 18.island) {
            ZStack {
                Circle().fill(.white.opacity(0.06))
                Image(systemName: "faceid")
                    .font(.system(size: 40.island, weight: .light))
                    .foregroundStyle(FaceEnrollmentPresentation.accent)
            }
            .frame(width: 94.island, height: 94.island)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8.island) {
                Text(unlock.isExperimental ? "Face Unlock · Experimental" : "Face Unlock")
                    .font(.system(size: 15.island, weight: .semibold))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.system(size: 12.island))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                HStack(spacing: 8.island) {
                    if unlock.hasPassword && (!unlock.isAuthorized || !unlock.isEnabled) {
                        IslandActionButton(title: "Authorize Face Unlock", systemImage: "lock.open", prominent: true) {
                            Task { await unlock.authorizeSession() }
                        }
                    }
                    IslandActionButton(title: controller.identities.isEmpty ? "Set up Face Unlock" : "Scan again",
                                       systemImage: "faceid", prominent: !unlock.hasPassword) {
                        controller.startMacUnlockEnrolment()
                    }
                    if unlock.hasPassword {
                        IslandActionButton(title: "Manage", systemImage: "slider.horizontal.3") {
                            model.requestSettings(pane: .faceCheck)
                        }
                    }
                }
                .disabled(controller.isPreparingEnrollment || controller.activity != .watching || unlock.isBusy)
                if !unlock.hasPassword && !controller.identities.isEmpty {
                    Button(unlock.setupUnavailableReason == nil ? "Set Mac password…" : "Use a saved face…") {
                        model.requestSettings(pane: .faceCheck)
                    }
                        .font(.system(size: 11.island, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .disabled(controller.isPreparingEnrollment || unlock.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20.island)
        .padding(.vertical, 10.island)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            guard !PerfTabCycler.isRequested else { return }
            controller.loadIdentities()
            unlock.refreshReadiness()
        }
    }

    private var statusLine: String {
        if controller.isPreparingEnrollment { return "Confirm with macOS to start a new face scan." }
        if unlock.setupUnavailableReason != nil, !controller.identities.isEmpty {
            return "Face saved. Automatic Mac unlocking is not available yet."
        }
        if unlock.isBusy { return "Authorizing Face Unlock…" }
        if case .failed(let message) = unlock.state { return message }
        if unlock.hasPassword {
            if !unlock.isAuthorized || !unlock.isEnabled { return "Your face and password are saved. Authorize Face Unlock for this session." }
            if !unlock.accessibilityGranted { return "Your face and password are saved. Open Manage to allow Accessibility." }
            return "Ready. When your Mac locks or wakes, look at the camera to unlock it."
        }
        if controller.cameraState == .denied { return "Allow Notchy in System Settings → Privacy & Security → Camera, then scan again." }
        if controller.identities.contains(where: { $0.isEnabled && $0.supportsPassiveUnlock }),
           unlock.setupUnavailableReason == nil { return "Your face is saved. Set your Mac password to enable automatic unlocking." }
        if !controller.status.isEmpty { return controller.status }
        return "Scan your face, then save your Mac login password."
    }
}

private struct IslandActionButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.island, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, 12.island)
                .padding(.vertical, 6.island)
                .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14)))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
