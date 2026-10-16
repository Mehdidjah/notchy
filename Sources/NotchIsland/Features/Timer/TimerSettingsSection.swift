import SwiftUI

/// Timer rows for the app's Settings window. Embed inside a `Form`.
struct TimerSettingsSection: View {
    @ObservedObject private var settings: TimerSettings

    init(settings: TimerSettings = .shared) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        Group {
            Section("Timer") {
                Toggle("Play a sound when the timer ends", isOn: $settings.soundEnabled)
                Picker("Sound", selection: $settings.soundName) {
                    ForEach(TimerSettings.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!settings.soundEnabled)
                Toggle("Send a notification when the timer ends", isOn: $settings.notificationsEnabled)
                Toggle("Show presets in the Timer tab", isOn: $settings.showsPresetsInTab)
                Picker("Progress style", selection: $settings.progressStyle) {
                    ForEach(TimerProgressStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .disabled(!settings.showsProgress)
                Picker("Colour", selection: $settings.iconColorMode) {
                    ForEach(TimerIconColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if settings.iconColorMode == .solid {
                    ColorPicker("Solid colour", selection: solidColor, supportsOpacity: false)
                }
            }

            Section("Closed Notch") {
                Toggle("Show the running timer on the closed notch", isOn: $settings.liveActivityEnabled)
                Group {
                    Toggle("Countdown", isOn: $settings.showsCountdown)
                    Toggle("Timer name", isOn: $settings.showsLabel)
                    Toggle("Progress", isOn: $settings.showsProgress)
                    Toggle("Pause and stop buttons", isOn: $settings.inlineControlsEnabled)
                }
                .disabled(!settings.liveActivityEnabled)
            }

            Section("Presets") {
                ForEach($settings.presets) { $preset in
                    TimerPresetEditorRow(preset: $preset) {
                        settings.removePreset(id: preset.id)
                    }
                }
                HStack {
                    Button("Add Preset") { settings.addPreset() }
                    Spacer()
                    Button("Restore Defaults") { settings.restoreDefaultPresets() }
                        .disabled(settings.presetsMatchDefaults)
                }
            }
        }
    }

    private var solidColor: Binding<Color> {
        Binding(
            get: { settings.solidColor.color },
            set: { settings.solidColor = TimerColorComponents(color: $0) }
        )
    }
}

/// Colour swatch, editable name, minute stepper and a delete button for one preset.
private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("Colour", selection: color, supportsOpacity: false)
                .labelsHidden()
            TextField("Name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Stepper(value: minutes, in: 1...600) {
                Text(preset.formattedDuration)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete preset")
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.colorComponents = TimerColorComponents(color: $0) }
        )
    }

    /// Whole minutes; seconds in an existing preset are kept until the stepper moves.
    private var minutes: Binding<Int> {
        Binding(
            get: { max(1, Int(preset.duration / 60)) },
            set: { preset.duration = TimeInterval($0 * 60) }
        )
    }
}
