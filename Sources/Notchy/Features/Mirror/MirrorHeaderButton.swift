import SwiftUI

/// The mirror button in the island header: a round chip with a `web.camera` glyph. A click
/// turns the camera mirror on or off, switching to Home first so the mirror is on screen.
/// Renders nothing while the mirror is switched off in Settings.
struct MirrorHeaderButton: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var controller: WebcamController
    @ObservedObject private var settings: MirrorSettings
    @ObservedObject private var layout = HomeLayoutState.shared

    init(model: NotchViewModel, controller: WebcamController = .shared) {
        self.model = model
        _controller = ObservedObject(wrappedValue: controller)
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        if settings.isEnabled {
            button
        }
    }

    private var button: some View {
        Button(action: press) {
            NotchChipFace(symbol: "web.camera", isSelected: controller.isPreviewRequested)
        }
        .buttonStyle(.plain)
        .onDisappear { controller.headerDidDisappear() }
        .help(controller.isPreviewRequested ? "Turn off the mirror" : "Show the camera mirror")
        .accessibilityLabel("Camera mirror")
        .accessibilityValue(controller.isSessionRunning ? "On" : "Off")
    }

    private func press() {
        if layout.showsMirror, model.selectedTab != .home {
            model.selectTab(.home)
        }
        controller.togglePreview(from: .headerButton)
    }
}
