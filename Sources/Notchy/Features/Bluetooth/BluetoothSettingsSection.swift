import SwiftUI

/// Bluetooth audio rows for the Settings window, grouped as the Bluetooth part of a
/// Devices pane. Returns `Section`s, so embed it inside a `Form`.
struct BluetoothSettingsSection: View {
    @ObservedObject private var settings: BluetoothSettings
    @ObservedObject private var monitor: BluetoothAudioMonitor
    private let controller: BluetoothHUDController

    init(
        settings: BluetoothSettings = .shared,
        monitor: BluetoothAudioMonitor = .shared,
        controller: BluetoothHUDController = .shared
    ) {
        _settings = ObservedObject(wrappedValue: settings)
        _monitor = ObservedObject(wrappedValue: monitor)
        self.controller = controller
    }

    var body: some View {
        // The rows are independent switches: none is greyed out by the master switch.
        Section {
            Toggle("Show Bluetooth device connections", isOn: $settings.showDeviceConnections)
            Toggle("Use circular battery indicator", isOn: $settings.useCircularBatteryIndicator)
            Toggle("Show battery percentage text in HUD", isOn: $settings.showBatteryPercentageText)
            Toggle("Scroll device name in HUD", isOn: $settings.showDeviceNameMarquee)
            // Kept here because this app has no global inline-HUD switch and does not read the
            // battery through private sources.
            Toggle("Show beside the notch", isOn: $settings.useInlineHUD)
            Toggle("Read headphone battery levels", isOn: $settings.readBatteryLevels)
            Button {
                controller.triggerTestHUD()
            } label: {
                Label("Test Bluetooth HUD", systemImage: "headphones")
            }
            .disabled(!settings.showDeviceConnections)
            if !monitor.connectedDevices.isEmpty {
                LabeledContent(
                    "Connected",
                    value: monitor.connectedDevices.map(\.name).joined(separator: ", ")
                )
            }
        } header: {
            Text("Bluetooth Audio Devices")
        } footer: {
            Text("Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        Section {
            Toggle("Color-coded battery display", isOn: $settings.useColorCodedBatteryDisplay)
            // Shown only while colour coding is on.
            if settings.useColorCodedBatteryDisplay {
                Toggle("Smooth color gradient", isOn: $settings.useSmoothColorGradient)
            }
        } header: {
            Text("Battery Indicator Styling")
        } footer: {
            Group {
                if settings.useSmoothColorGradient {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                }
            }
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }
}
