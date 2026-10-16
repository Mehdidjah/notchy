import SwiftUI

/// The colour picker's rows for the Settings window. Returns a `Section`, so embed it inside a
/// `Form` (for example the Notch tab's grouped form).
struct ColorPickerSettingsSection: View {
    @ObservedObject private var settings: ColorPickerSettings
    @ObservedObject private var service: ColorPickerService

    init(service: ColorPickerService = .shared) {
        _service = ObservedObject(wrappedValue: service)
        _settings = ObservedObject(wrappedValue: service.settings)
    }

    var body: some View {
        Section("Color Picker") {
            Toggle("Enable color picker", isOn: $settings.isEnabled)
            Toggle("Show eyedropper in island header", isOn: $settings.showHeaderButton)
                .disabled(!settings.isEnabled)
            Picker("Copy format after picking", selection: $settings.defaultFormat) {
                ForEach(PickedColorFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .disabled(!settings.isEnabled)
            Picker("Recent colors shown", selection: $settings.historySize) {
                ForEach(ColorPickerSettings.historySizeChoices, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .disabled(!settings.isEnabled)
            Toggle("Show every color format", isOn: $settings.showAllFormats)
                .disabled(!settings.isEnabled)
            LabeledContent(
                "Stored colors",
                value: "\(service.history.count) of \(ColorPickerService.maximumStoredColors)"
            )
            Button("Clear color history", role: .destructive) { service.clearHistory() }
                .disabled(service.history.isEmpty)
            Text("Click the eyedropper to sample a color; right-click it for recent colors. Picked colors are copied in the chosen format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
