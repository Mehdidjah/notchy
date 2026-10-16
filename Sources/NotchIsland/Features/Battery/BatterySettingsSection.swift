import SwiftUI

/// Battery rows for the Settings window, laid out like Atoll's Battery pane. Returns
/// `Section`s, so embed it inside a `Form`.
struct BatterySettingsSection: View {
    @ObservedObject private var settings: BatterySettings
    @ObservedObject private var monitor: BatteryMonitor
    private let controller: BatteryHUDController

    init(
        settings: BatterySettings = .shared,
        monitor: BatteryMonitor = .shared,
        controller: BatteryHUDController = .shared
    ) {
        _settings = ObservedObject(wrappedValue: settings)
        _monitor = ObservedObject(wrappedValue: monitor)
        self.controller = controller
    }

    var body: some View {
        if monitor.hasLoaded, !monitor.state.hasBattery {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "battery.100percent.slash")
                        .font(.title)
                    Text("Battery settings and informations are only available on MacBooks")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            sections
        }
    }

    @ViewBuilder
    private var sections: some View {
        Section {
            Toggle("Show battery indicator", isOn: $settings.showBatteryIndicator)
            Toggle("Show power status notifications", isOn: $settings.showPowerStatusNotifications)
            Toggle("Play low battery alert sound", isOn: $settings.playLowBatteryAlertSound)
        } header: {
            Text("General")
        }

        Section {
            Toggle("Show battery percentage", isOn: $settings.showBatteryPercentage)
            Toggle("Show power status icons", isOn: $settings.showPowerStatusIcons)
            // Atoll keeps this one under General > UI Mode, greyed out without a battery
            // indicator; this app has no UI-mode pane, so it sits with the other battery rows.
            Toggle("Show battery percentage inside icon", isOn: $settings.showBatteryPercentInside)
                .disabled(!settings.showBatteryIndicator)
        } header: {
            Text("Battery Information")
        }

        Section {
            Toggle("Charging HUD", isOn: $settings.showChargingHUD)
            Toggle("Low battery HUD", isOn: $settings.showLowBatteryHUD)
            Toggle("Fully charged HUD", isOn: $settings.showFullBatteryHUD)
        } header: {
            Text("Battery HUDs")
        } footer: {
            Text("These temporary HUDs recreate the charging, low-battery, and full-battery notch alerts.")
        }

        Section {
            secondsSlider("Charging duration", value: $settings.chargingHUDDuration, enabled: isEnabled(.charging))
            secondsSlider("Low battery duration", value: $settings.lowBatteryHUDDuration, enabled: isEnabled(.lowBattery))
            secondsSlider("Full battery duration", value: $settings.fullBatteryHUDDuration, enabled: isEnabled(.fullBattery))
        } header: {
            Text("HUD Duration")
        }

        Section {
            Button {
                controller.triggerTestHUD(.charging)
            } label: {
                Label("Test charging HUD", systemImage: "bolt.fill")
            }
            .disabled(!isEnabled(.charging))
            Button {
                controller.triggerTestHUD(.lowBattery)
            } label: {
                Label("Test low battery HUD", systemImage: "battery.25")
            }
            .disabled(!isEnabled(.lowBattery))
            Button {
                controller.triggerTestHUD(.fullBattery)
            } label: {
                Label("Test full battery HUD", systemImage: "battery.100")
            }
            .disabled(!isEnabled(.fullBattery))
        } header: {
            Text("HUD Tests")
        } footer: {
            Text("Runs the real notch animation on the current target display.")
        }

        Section {
            VStack(alignment: .leading, spacing: 10) {
                stylePicker("Low battery style", selection: $settings.lowBatteryHUDStyle)
                Text("Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            percentSlider(
                "Low battery threshold",
                value: $settings.lowBatteryThreshold,
                range: BatterySettings.lowThresholdRange
            )
        } header: {
            Text("Low Battery")
        }
        .disabled(!isEnabled(.lowBattery))
        .opacity(isEnabled(.lowBattery) ? 1 : 0.5)

        Section {
            VStack(alignment: .leading, spacing: 10) {
                stylePicker("Full battery style", selection: $settings.fullBatteryHUDStyle)
                Text("Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            percentSlider(
                "Full charge threshold",
                value: $settings.fullBatteryThreshold,
                range: BatterySettings.fullThresholdRange
            )
        } header: {
            Text("Full Battery")
        }
        .disabled(!isEnabled(.fullBattery))
        .opacity(isEnabled(.fullBattery) ? 1 : 0.5)
    }

    private func isEnabled(_ kind: BatteryHUDKind) -> Bool {
        settings.showPowerStatusNotifications && settings.isHUDEnabled(kind)
    }

    /// Atoll's segmented row: the title, a flexible gap of at least 8 pt, then the control.
    private func stylePicker(_ title: String, selection: Binding<BatteryHUDStyle>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(BatteryHUDStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func secondsSlider(_ title: String, value: Binding<Int>, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(value.wrappedValue)s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: Self.doubleBinding(value), in: Self.doubleRange(BatterySettings.durationRange), step: 1)
                .accessibilityLabel(title)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private func percentSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(value.wrappedValue)%")
                    .foregroundStyle(.secondary)
            }
            Slider(value: Self.doubleBinding(value), in: Self.doubleRange(range), step: 1)
                .accessibilityLabel(title)
        }
    }

    private static func doubleBinding(_ value: Binding<Int>) -> Binding<Double> {
        Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = Int($0.rounded()) }
        )
    }

    private static func doubleRange(_ range: ClosedRange<Int>) -> ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }
}
