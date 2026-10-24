import AppKit
import Combine
import SwiftUI

/// Keeps an explicit check usable when the island is disabled or hidden in fullscreen.
@MainActor
final class FaceCheckWindowController: NSObject, NSWindowDelegate {
    private let controller: FaceCheckController
    private var panel: NSPanel?
    private var observation: AnyCancellable?
    private var privacyObserver: AnyCancellable?
    private var hideFromScreenCapture = false

    init(controller: FaceCheckController, settings: UserSettings) {
        self.controller = controller
        super.init()
        observation = controller.liveActivity.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
            if phase == .hidden { self?.hide() }
        }
        privacyObserver = settings.$hideFromScreenCapture.removeDuplicates().sink { [weak self] hidden in
            self?.hideFromScreenCapture = hidden
            self?.panel?.sharingType = hidden ? .none : .readOnly
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView:
            FaceCheckActivityView(activity: controller.liveActivity, emblemSize: FaceEnrollmentPresentation.ringDiameter)
                .frame(width: 320, height: 344)
                .background(Color.black)
                .onExitCommand { [weak controller] in controller?.cancelVerification() }
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    func windowWillClose(_ notification: Notification) {
        controller.cancelVerification()
        panel?.contentView = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 344),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Face Check"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.sharingType = hideFromScreenCapture ? .none : .readOnly
        return panel
    }
}
