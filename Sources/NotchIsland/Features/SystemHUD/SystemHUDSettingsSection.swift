import AppKit
import SwiftUI

/// The system HUD rows for the Settings window, in the order of Atoll's "Controls" pane:
/// an Accessibility callout while the permission is missing, Controls, Audio feedback,
/// Dynamic Island Progress Bars, Appearance and Step size. Returns several `Section`s, so
/// embed it inside a grouped `Form`. Atoll keeps the Caps Lock rows in its Live Activities
/// pane; pass `includesCapsLock: false` and show `CapsLockSettingsSection` there to match.
struct SystemHUDSettingsSection: View {
    @ObservedObject private var settings: SystemHUDSettings
    @ObservedObject private var interceptor: SystemHUDMediaKeyInterceptor
    private let includesCapsLock: Bool

    init(
        includesCapsLock: Bool = true,
        settings: SystemHUDSettings = .shared,
        interceptor: SystemHUDMediaKeyInterceptor = .shared
    ) {
        self.includesCapsLock = includesCapsLock
        _settings = ObservedObject(wrappedValue: settings)
        _interceptor = ObservedObject(wrappedValue: interceptor)
    }

    var body: some View {
        Group {
            if !interceptor.isAccessibilityTrusted {
                Section {
                    accessibilityCallout
                } header: {
                    Text("Accessibility")
                }
            }

            Section {
                Toggle("Enable system HUD", isOn: $settings.enableSystemHUD)
                Toggle("Volume HUD", isOn: $settings.enableVolumeHUD)
                    .disabled(!settings.enableSystemHUD)
                Toggle("Brightness HUD", isOn: $settings.enableBrightnessHUD)
                    .disabled(!settings.enableSystemHUD)
                Toggle("Microphone HUD", isOn: $settings.enableMicrophoneHUD)
                    .disabled(!settings.enableSystemHUD)
                Toggle("Intercept volume keys", isOn: $settings.interceptMediaKeys)
                    .disabled(!settings.enableSystemHUD || !settings.enableVolumeHUD)
                    .onChange(of: settings.interceptMediaKeys) { _, enabled in
                        if enabled { interceptor.requestAccessibility() }
                    }
            } header: {
                Text("Controls")
            } footer: {
                Text("Choose which system controls should display HUD notifications.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Play feedback when volume is changed", isOn: $settings.playVolumeFeedback)
                    .help("Plays a short click whenever you press the hardware volume keys.")
            } header: {
                Text("Audio feedback")
            } footer: {
                Text("Requires Accessibility permission so NotchIsland can intercept the hardware volume keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Color-coded volume display", isOn: $settings.colorCodedVolume)
                    .disabled(colorCodingDisabled)
                if !colorCodingDisabled && settings.colorCodedVolume {
                    Toggle("Smooth color transitions", isOn: $settings.smoothColorGradient)
                }
                Toggle("Show percentages beside progress bars", isOn: $settings.showPercentages)
            } header: {
                Text("Dynamic Island Progress Bars")
            } footer: {
                Text(progressFooter)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Picker("HUD style", selection: styleBinding) {
                    ForEach(SystemHUDStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Picker("Progressbar style", selection: $settings.progressBarStyle) {
                    ForEach(SystemHUDProgressBarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Toggle("Enable glowing effect", isOn: $settings.glowEffect)
                Toggle("Use accent color", isOn: $settings.useAccentColor)
            } header: {
                Text("Appearance")
            }

            Section {
                stepRow("Volume step", value: $settings.volumeStepPercent)
                stepRow("Volume fine step", value: $settings.volumeFineStepPercent)
            } header: {
                Text("Step size")
            } footer: {
                Text("Percent change per key press. Fine step applies when holding Shift+Option. Brightness keys are left to macOS, which still sets the level; the island shows the new level as it changes.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if includesCapsLock {
                CapsLockSettingsSection(settings: settings)
            }
        }
        .onAppear { interceptor.refreshAccessibility() }
    }

    /// Atoll resets the glow and bar style inside `withAnimation` when Inline is chosen.
    private var styleBinding: Binding<SystemHUDStyle> {
        Binding(
            get: { settings.style },
            set: { newValue in withAnimation { settings.style = newValue } }
        )
    }

    private var accessibilityCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Accessibility permission lets NotchIsland replace the native volume HUD.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            HStack(spacing: 8) {
                Button("Request Access") { interceptor.requestAccessibility() }
                Button("Open System Settings") { openAccessibilitySettings() }
            }
        }
        .padding(.vertical, 4)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private var colorCodingDisabled: Bool {
        settings.progressBarStyle == .segmented
    }

    private var progressFooter: String {
        if colorCodingDisabled {
            return "Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options."
        }
        if settings.smoothColorGradient {
            return "Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill."
        }
        return "Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%)."
    }

    private func stepRow(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: SystemHUDSettings.stepRange) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .disabled(!settings.interceptMediaKeys || !settings.enableSystemHUD || !settings.enableVolumeHUD)
    }
}

/// Atoll's "Caps Lock Indicator" section (Live Activities pane).
struct CapsLockSettingsSection: View {
    @ObservedObject private var settings: SystemHUDSettings

    init(settings: SystemHUDSettings = .shared) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        Section {
            Toggle("Show Caps Lock Indicator", isOn: $settings.enableCapsLockIndicator)
            Toggle("Show Caps Lock label", isOn: $settings.showCapsLockLabel)
                .disabled(!settings.enableCapsLockIndicator)
            Picker("Caps Lock color", selection: $settings.capsLockTint) {
                ForEach(CapsLockTintMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.enableCapsLockIndicator)
        } header: {
            Text("Caps Lock Indicator")
        } footer: {
            Text("Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
