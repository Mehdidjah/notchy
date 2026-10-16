import SwiftUI

/// Focus rows for the Settings window. Returns a `Section`; embed it in a `Form`.
struct FocusSettingsSection: View {
    @ObservedObject private var settings: FocusSettings
    @ObservedObject private var monitor: FocusMonitor

    init(monitor: FocusMonitor = .shared) {
        _monitor = ObservedObject(wrappedValue: monitor)
        _settings = ObservedObject(wrappedValue: monitor.settings)
    }

    var body: some View {
        Section {
            if !monitor.hasFullDiskAccess {
                FocusPermissionCallout(
                    openSettings: { FocusMonitor.openFullDiskAccessSettings() },
                    checkAgain: { monitor.refreshAccess() }
                )
            }

            Toggle("Enable Focus Detection", isOn: $settings.enableDoNotDisturbDetection)
            Toggle("Show Focus Indicator", isOn: $settings.showDoNotDisturbIndicator)
                .disabled(!settings.enableDoNotDisturbDetection)
            Toggle("Show Focus Label", isOn: $settings.showDoNotDisturbLabel)
                .disabled(!settings.enableDoNotDisturbDetection || settings.focusIndicatorNonPersistent)
                .help(settings.focusIndicatorNonPersistent
                    ? "Labels are forced to compact on/off text while brief toast mode is enabled."
                    : "Show the active Focus name inside the indicator.")
            Toggle("Show Focus as brief toast", isOn: $settings.focusIndicatorNonPersistent)
                .disabled(!settings.enableDoNotDisturbDetection)
                .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")
            Picker("Focus detection mode", selection: $settings.monitoringMode) {
                ForEach(FocusMonitoringMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .disabled(!settings.enableDoNotDisturbDetection)

            LabeledContent("Focus Status") {
                if !monitor.isMonitoring {
                    Text("Disabled").foregroundStyle(.secondary)
                } else if monitor.isActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                        Text(monitor.modeName.isEmpty ? "Focus Enabled" : monitor.modeName)
                            .foregroundStyle(Color.purple)
                    }
                } else {
                    Text("Active - No Focus").foregroundStyle(.green)
                }
            }
        } header: {
            Text("Do Not Disturb")
        } footer: {
            Text("Listens for Focus session changes via distributed notifications. \"Use DevTools\" also reads Focus names from the unified log.")
        }
    }
}

/// The Full Disk Access card at the top of the section: a purple drive glyph and title, a
/// caption, and two small buttons, on a faint rounded panel.
/// Full Disk Access cannot be requested by an app, so the first button opens the pane.
private struct FocusPermissionCallout: View {
    let openSettings: () -> Void
    let checkAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Custom Focus metadata", systemImage: "externaldrive.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.purple)

            Text("Full Disk Access lets Notchy tell which Focus is on and use custom Focus icons, colors and labels. Focus on/off detection still works without it; grant access only if you want personalized indicators.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Open Privacy & Security", action: openSettings)
                    .buttonStyle(.borderedProminent)
                Button("Check Again", action: checkAgain)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
