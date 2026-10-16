import SwiftUI

/// Privacy indicator rows for the Settings window. Returns a `Section`; embed it in a `Form`.
struct PrivacySettingsSection: View {
    @ObservedObject private var settings: PrivacySettings
    @ObservedObject private var monitor: PrivacyMonitor

    init(monitor: PrivacyMonitor = .shared) {
        _monitor = ObservedObject(wrappedValue: monitor)
        _settings = ObservedObject(wrappedValue: monitor.settings)
    }

    var body: some View {
        Section {
            Toggle("Enable Camera Detection", isOn: $settings.enableCameraDetection)
            Toggle("Enable Microphone Detection", isOn: $settings.enableMicrophoneDetection)

            if monitor.isMonitoring {
                LabeledContent("Camera Status") {
                    status(
                        active: settings.enableCameraDetection && monitor.cameraInUse,
                        activeText: "Camera Active",
                        tint: .green
                    )
                }
                LabeledContent("Microphone Status") {
                    status(
                        active: settings.enableMicrophoneDetection && monitor.microphoneInUse,
                        activeText: "Microphone Active",
                        tint: .yellow
                    )
                }
            }
        } header: {
            Text("Privacy Indicators")
        } footer: {
            Text("Shows a green camera icon and an orange microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs.")
        }
    }

    @ViewBuilder
    private func status(active: Bool, activeText: String, tint: Color) -> some View {
        if active {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(activeText).foregroundStyle(tint)
            }
        } else {
            Text("Inactive").foregroundStyle(.secondary)
        }
    }
}
