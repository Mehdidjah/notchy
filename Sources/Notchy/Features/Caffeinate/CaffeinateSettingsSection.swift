import SwiftUI

/// Keep Awake rows for the Settings window, as in Atoll's General tab. Returns a `Section`, so
/// embed it inside a `Form`.
struct CaffeinateSettingsSection: View {
    @ObservedObject private var settings: CaffeinateSettings

    init(settings: CaffeinateSettings = .shared) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        Section {
            Toggle("Enable Keep Awake", isOn: $settings.isEnabled)

            Toggle("Show Keep Awake icon in the notch", isOn: $settings.showHeaderButton)
                .disabled(!settings.isEnabled)

            Picker("Default duration", selection: $settings.defaultDuration) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    Text(duration.displayName).tag(duration)
                }
            }
            .disabled(!settings.isEnabled)

            Toggle("Also keep the display awake", isOn: $settings.keepsDisplayAwake)
                .disabled(!settings.isEnabled)
        } header: {
            Text("Keep Awake")
        } footer: {
            Text("Holds a power assertion so the Mac will not sleep, the way the caffeinate command does. Turning this off also ends a session that is already running. With the display option off, the screen can still sleep while the system stays up.")
        }
    }
}
