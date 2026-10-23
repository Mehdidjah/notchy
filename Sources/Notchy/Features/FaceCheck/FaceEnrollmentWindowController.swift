import AppKit
import Combine
import SwiftUI

@MainActor
final class FaceEnrollmentSurface: ObservableObject {
    @Published var expanded = false
    @Published var phase: FaceEnrollmentScanPhase = .scanning
}

/// Enrollment temporarily owns the top of the display and a camera-preview lease. Keeping
/// that lease outside the Face tab prevents its disappearance from cancelling the scan.
@MainActor
final class FaceEnrollmentWindowController {
    private let controller: FaceCheckController
    private let surface = FaceEnrollmentSurface()
    private let setup: FaceUnlockSetupSession
    private let previewID = UUID()
    private var ownsPreview = false
    private var panel: NSPanel?
    private var sweep: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var displayObserver: AnyCancellable?
    private var privacyObserver: AnyCancellable?
    private var setupObserver: AnyCancellable?
    private var hideFromScreenCapture = false
    private var generation = 0
    private var closing = false
    private(set) var isPresented = false
    var onPresentationChanged: ((Bool) -> Void)?

    init(controller: FaceCheckController, settings: UserSettings, unlock: MacUnlockController = .shared) {
        self.controller = controller
        setup = FaceUnlockSetupSession(unlock: unlock)
        setup.onFinished = { [weak self] in self?.hide() }
        setupObserver = setup.$stage.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] stage in
                guard let self, isPresented, !closing, stage.showsCredentialStep else { return }
                sweep?.orderOut(nil)
                if stage == .password { panel?.makeKeyAndOrderFront(nil) }
            }
        hideFromScreenCapture = settings.hideFromScreenCapture
        privacyObserver = settings.$hideFromScreenCapture.removeDuplicates()
            .sink { [weak self] hidden in self?.setCapturePrivacy(hidden) }
        displayObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPresented else { return }
                self.position(on: FaceCheckDisplay.resolve(FaceCheckPreferences.shared.options.displayID))
            }
    }

    func present(on screen: NSScreen?, forMacUnlock: Bool = false) {
        dismissal?.cancel()
        generation &+= 1
        if forMacUnlock { setup.beginCapture() } else { setup.reset() }
        if !ownsPreview {
            ownsPreview = true
            controller.retainPreview(previewID, start: false)
        }
        surface.phase = .scanning
        surface.expanded = false
        closing = false
        isPresented = true
        onPresentationChanged?(true)
        panel = panel ?? Self.makePanel(level: 4, interactive: true)
        sweep = sweep ?? Self.makePanel(level: 2, interactive: false)
        setCapturePrivacy(hideFromScreenCapture)
        position(on: screen)
        panel?.makeKeyAndOrderFront(nil)
        sweep?.orderFrontRegardless()
        let current = generation
        Task { @MainActor [weak self] in
            // Give the hosting view a collapsed frame before starting the opening spring.
            try? await Task.sleep(for: .milliseconds(20))
            guard let self, self.isPresented, self.generation == current else { return }
            self.surface.expanded = true
        }
    }

    func saved(identity: FaceIdentity) {
        guard isPresented, !closing else { return }
        surface.phase = .saved
        releaseCamera()
        dismissal?.cancel()
        if setup.stage == .capturing {
            setup.saved(identity)
            return
        }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: FaceEnrollmentPresentation.completionHold)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func ended(message: String?) {
        guard isPresented, !closing else { return }
        if let message {
            surface.phase = .failed(message)
            releaseCamera()
        } else { hide() }
    }

    func hide(immediately: Bool = false) {
        guard isPresented else { return }
        closing = true
        dismissal?.cancel()
        setup.cancel()
        controller.cancelMacUnlockEnrolmentAuthorization()
        generation &+= 1
        surface.expanded = false
        sweep?.orderOut(nil)
        releaseCamera()
        if immediately { finishHiding(); return }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: FaceEnrollmentPresentation.closeDuration)
            guard !Task.isCancelled else { return }
            self?.finishHiding()
        }
    }

    private func finishHiding() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        sweep?.contentView = nil
        setup.reset()
        isPresented = false
        onPresentationChanged?(false)
    }

    private func releaseCamera() {
        guard ownsPreview else { return }
        ownsPreview = false
        controller.releasePreview(previewID)
    }

    private func cancel() {
        if controller.activity == .enrolling { controller.cancelEnrolment() }
        else { hide() }
    }

    private func setCapturePrivacy(_ hidden: Bool) {
        hideFromScreenCapture = hidden
        panel?.sharingType = hidden ? .none : .readOnly
        sweep?.sharingType = hidden ? .none : .readOnly
    }

    private func position(on preferred: NSScreen?) {
        guard let screen = preferred ?? NSScreen.main else { return }
        let geometry = NotchGeometryResolver.resolve(screen: screen)
        let size = CGSize(width: geometry.isHardwareNotch ? 412 : 380,
                          height: geometry.isHardwareNotch ? 344 : 350)
        let topGap: CGFloat = geometry.isHardwareNotch ? 0 : 8
        panel?.setFrame(CGRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height - topGap,
                              width: size.width, height: size.height), display: true)
        panel?.contentView = NSHostingView(rootView: FaceEnrollmentLiveView(
            controller: controller, surface: surface, setup: setup, geometry: geometry,
            cancel: { [weak self] in self?.cancel() },
            retry: { [weak self] in self?.controller.restartEnrolment() }
        ))
        sweep?.setFrame(screen.frame, display: true)
        sweep?.contentView = NSHostingView(rootView: FaceEnrollmentLiveSweep(controller: controller, surface: surface))
    }

    private static func makePanel(level: Int, interactive: Bool) -> NSPanel {
        let panel = FaceEnrollmentPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        panel.title = interactive ? "Face enrollment" : "Face enrollment direction"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = !interactive
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + level)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }
}

private final class FaceEnrollmentPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

private struct FaceEnrollmentLiveView: View {
    @ObservedObject var controller: FaceCheckController
    @ObservedObject var surface: FaceEnrollmentSurface
    @ObservedObject var setup: FaceUnlockSetupSession
    var geometry: NotchGeometry
    var cancel: () -> Void
    var retry: () -> Void

    var body: some View {
        FaceUnlockSetupSurface(stage: setup.stage, hasHardwareNotch: geometry.isHardwareNotch,
                               isExpanded: surface.expanded,
                               compactWidth: geometry.syntheticOrHardwareWidth + 32,
                               compactHeight: geometry.topInset) {
            scan
        } steps: {
            FaceUnlockSetupStepView(session: setup, hasHardwareNotch: geometry.isHardwareNotch,
                                    isExpanded: surface.expanded,
                                    compactWidth: geometry.syntheticOrHardwareWidth + 32,
                                    compactHeight: geometry.topInset, cancel: cancel)
        }
    }

    private var scan: some View {
        FaceEnrollmentScanView(counts: controller.poseCounts,
                               heading: .init(yaw: controller.face?.yaw, pitch: controller.face?.pitch),
                               instruction: controller.enrollmentInstruction,
                               phase: controller.activity == .saving ? .saving : surface.phase,
                               hasHardwareNotch: geometry.isHardwareNotch,
                               isExpanded: surface.expanded,
                               compactWidth: geometry.syntheticOrHardwareWidth + 32,
                               compactHeight: geometry.topInset,
                               drawsBackground: false,
                               cancel: cancel, retry: retry) {
            FaceCheckPreview(session: controller.camera.session, faceBounds: nil)
                .background(.black)
        }
    }
}

private struct FaceEnrollmentLiveSweep: View {
    @ObservedObject var controller: FaceCheckController
    @ObservedObject var surface: FaceEnrollmentSurface

    var body: some View {
        let target = FaceEnrollmentPresentation.nextPose(counts: controller.poseCounts,
                                                         samplesPerPose: controller.samplesPerPose)
        let active = surface.expanded && surface.phase == .scanning && controller.activity == .enrolling
            && controller.enrollmentIsLive && controller.face != nil
        FaceEnrollmentSweepView(direction: active ? target.flatMap(FaceEnrollmentPresentation.angle) : nil)
    }
}
