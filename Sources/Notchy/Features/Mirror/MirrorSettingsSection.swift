import SwiftUI

/// Camera mirror rows for the Settings window, as in Atoll's "Additional features" group of
/// the Appearance pane: Enable Dynamic mirror, Mirror shape (Circle, Square) and Mirror
/// Camera. Returns a `Section`, so embed it inside a `Form`.
struct MirrorSettingsSection: View {
    @ObservedObject private var settings: MirrorSettings
    @ObservedObject private var controller: WebcamController

    init(controller: WebcamController = .shared) {
        _controller = ObservedObject(wrappedValue: controller)
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        Section {
            Toggle("Enable Dynamic mirror", isOn: $settings.isEnabled)
                // Atoll greys this out on Macs without a camera; it can still be turned off.
                .disabled(!controller.cameraAvailable && !settings.isEnabled)

            Picker("Mirror shape", selection: $settings.shape) {
                Text(MirrorShape.circle.displayName).tag(MirrorShape.circle)
                Text(MirrorShape.rectangle.displayName).tag(MirrorShape.rectangle)
            }

            if controller.cameraAvailable {
                Picker("Mirror Camera", selection: $settings.cameraID) {
                    Text("Automatic").tag("")
                    ForEach(controller.availableCameras) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                    if !settings.cameraID.isEmpty,
                       !controller.availableCameras.contains(where: { $0.id == settings.cameraID }) {
                        Text("Disconnected camera").tag(settings.cameraID)
                    }
                }
            }

            if controller.authorization.isBlocked {
                LabeledContent("Camera access") {
                    Button("Open Privacy Settings") { WebcamController.openCameraPrivacySettings() }
                }
            }
        } header: {
            // Atoll's group heading for the mirror rows (Appearance pane); it has no footer.
            Text("Additional features")
        }
        .onAppear {
            controller.refreshCameras()
            controller.refreshAuthorization()
        }
    }
}
