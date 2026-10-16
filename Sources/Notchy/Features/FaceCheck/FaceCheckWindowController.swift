import AppKit
import Combine
import SwiftUI

/// Keeps an explicit check usable when the island is disabled or hidden in fullscreen.
@MainActor
final class FaceCheckWindowController: NSObject, NSWindowDelegate {
    private let controller: FaceCheckController
    private var panel: NSPanel?
    private var observation: AnyCancellable?

    init(controller: FaceCheckController) {
        self.controller = controller
        super.init()
        observation = controller.liveActivity.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
            if phase == .hidden { self?.hide() }
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView:
            FaceCheckActivityView(activity: controller.liveActivity)
                .frame(width: 284, height: 202)
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 284, height: 202),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Face Check"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        return panel
    }
}
