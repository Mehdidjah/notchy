import SwiftUI

/// Home-tab camera mirror, as in Atoll: a square (or circle) tile as tall as the Home row that
/// shows the front camera, flipped like a mirror. Until the camera is turned on it shows a dark
/// "Mirror" tile with a camera glyph 1/3.5 of its width ("Access Denied" with a warning glyph
/// when permission was refused). A click turns the camera on or off; the camera stops whenever
/// the tile leaves the screen. Keep this type name and its initialiser; the Home tab calls it.
struct HomeMirrorSlot: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var controller: WebcamController
    @ObservedObject private var settings: MirrorSettings
    @State private var slotID = UUID()

    init(model: NotchViewModel) {
        self.model = model
        _controller = ObservedObject(wrappedValue: WebcamController.shared)
        _settings = ObservedObject(wrappedValue: WebcamController.shared.settings)
    }

    private var isOpen: Bool { model.state.showsShelfContent }

    /// The outline that takes clicks: the live preview's or the placeholder's.
    private var hitRadius: CGFloat {
        controller.isSessionRunning ? settings.shape.previewCornerRadius : settings.shape.placeholderCornerRadius
    }

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack {
                if let session = controller.backend.captureSession {
                    MirrorCameraPreview(session: session, cornerRadius: settings.shape.previewCornerRadius)
                        .clipShape(RoundedRectangle(cornerRadius: settings.shape.previewCornerRadius))
                        .frame(width: side, height: side)
                        .opacity(controller.isSessionRunning ? 1 : 0)
                }

                if !controller.isSessionRunning {
                    MirrorPlaceholderTile(
                        side: side,
                        cornerRadius: settings.shape.placeholderCornerRadius,
                        // Atoll switches the caption on `.denied` only.
                        isAccessDenied: controller.authorization == .denied
                    )
                }
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: hitRadius))
            .onTapGesture { controller.togglePreview(from: .mirror) }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaledToFit()
        .opacity(isOpen ? 1 : 0)
        .blur(radius: isOpen ? 0 : 20)
        .onAppear { controller.setMirror(slotID, visible: isOpen) }
        .onChange(of: isOpen) { _, open in controller.setMirror(slotID, visible: open) }
        .onDisappear { controller.setMirror(slotID, visible: false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera mirror")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.togglePreview(from: .mirror) }
    }

    private var accessibilityValue: String {
        if controller.authorization == .denied { return "Camera access denied" }
        return controller.isSessionRunning ? "On" : "Off"
    }
}

/// The tile shown while the camera is off: a #141414 fill, a 1-pt white rim at 4%, a grey
/// glyph at 1/3.5 of the side and a grey `.caption2` caption 8 pt below it.
private struct MirrorPlaceholderTile: View {
    let side: CGFloat
    let cornerRadius: CGFloat
    let isAccessDenied: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255))
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: side, height: side)
            VStack(spacing: 8) {
                Image(systemName: isAccessDenied ? "exclamationmark.triangle" : "web.camera")
                    .foregroundStyle(Color.gray)
                    .font(.system(size: max(1, side / 3.5)))
                Text(isAccessDenied ? "Access Denied" : "Mirror")
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
            }
        }
    }
}
