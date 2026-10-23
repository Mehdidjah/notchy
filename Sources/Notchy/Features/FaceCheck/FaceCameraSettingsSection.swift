import AppKit
import SwiftUI

struct FaceCameraSettingsSection: View {
    @ObservedObject var controller: FaceCheckController
    @ObservedObject var preferences: FaceCheckPreferences
    @ObservedObject var devices: FaceCheckDeviceCatalog
    @State private var previewID = UUID()

    var body: some View {
        Section("Camera") {
            cameraPicker("Default", selection: $preferences.options.defaultCameraID, inherits: false)
            cameraPicker("Built-in display", selection: $preferences.options.builtInCameraID, inherits: true)
            cameraPicker("External display", selection: $preferences.options.externalCameraID, inherits: true)
            HStack {
                Text("Display overrides apply to preview, enrollment, and unlocking.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { devices.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh cameras")
            }
        }
        .disabled(controller.activity != .watching)
        Section("Preview") {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.85))
                if controller.cameraState == .on || controller.cameraState == .starting {
                    FaceCheckPreview(session: controller.camera.session, faceBounds: controller.face?.bounds)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    if controller.cameraState == .starting { ProgressView().tint(.white) }
                } else {
                    Button("Show preview") { controller.startCamera() }.buttonStyle(.borderedProminent)
                }
            }.frame(height: 240)
            if controller.cameraState == .on || controller.cameraState == .starting {
                HStack {
                    Text("Mirrored preview · \(FaceCheckDisplay.resolve(preferences.options.displayID)?.localizedName ?? "Main display")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Hide preview") { controller.stopCamera() }
                }
            }
            if controller.cameraState == .denied {
                Button("Open Camera privacy settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
            if let problem = controller.problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            Text("If a selected camera is disconnected, connect it or choose System default. Notchy won't silently switch to another camera.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { devices.refresh(); controller.retainPreview(previewID, start: false) }
        .onDisappear { controller.releasePreview(previewID) }
    }

    private func cameraPicker(_ title: String, selection: Binding<String>, inherits: Bool) -> some View {
        Picker(title, selection: selection) {
            Text(inherits ? "Use default camera" : "System default").tag("")
            ForEach(devices.cameras) { Text($0.name).tag($0.id) }
            if !selection.wrappedValue.isEmpty, !devices.cameras.contains(where: { $0.id == selection.wrappedValue }) {
                Text("Selected camera disconnected").tag(selection.wrappedValue)
            }
        }
    }
}
