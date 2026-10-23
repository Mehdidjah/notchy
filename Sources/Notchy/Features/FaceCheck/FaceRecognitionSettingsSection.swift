import SwiftUI

struct FaceRecognitionSettingsSection: View {
    @ObservedObject var preferences: FaceCheckPreferences

    private var validated: Bool { FaceModelValidation.bundled != nil }

    var body: some View {
        Section("Recognition") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Match confidence").fontWeight(.medium)
                Slider(value: Binding(get: { max(validated ? 1 : 0, preferences.options.matchConfidence) },
                                      set: { preferences.options.matchConfidence = $0 }),
                       in: (validated ? 1.0 : 0.0)...2, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Match confidence")
                HStack {
                    Text(validated ? "Default" : "Less strict")
                    Spacer()
                    if !validated { Text("Default"); Spacer() }
                    Text("More strict")
                }.font(.caption).foregroundStyle(.secondary)
                Text(validated ? "Choose Default or require a closer face match." : "Less strict accepts a wider face match. More strict may take longer to recognize you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Detection distance").fontWeight(.medium)
                Slider(value: $preferences.options.detectionDistance, in: 0...2, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Detection distance")
                HStack { Text("Close"); Spacer(); Text("Default"); Spacer(); Text("Far") }
                    .font(.caption).foregroundStyle(.secondary)
                Text("Far allows a smaller face in the camera. Keep your face clearly visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Liveness") {
            Toggle("Liveness detection", isOn: $preferences.options.livenessEnabled)
            Text("Checks for photos and screens. Turning this off pauses Mac Face Unlock; your saved face and password stay encrypted.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(FaceLivenessStrength.allCases) { strength in
                    FaceOptionTile(title: strength.title, symbol: strength == .light ? "sun.min" : "sun.max",
                                   selected: preferences.options.livenessStrength == strength) {
                        preferences.options.livenessStrength = strength
                    }
                }
            }.disabled(!preferences.options.livenessEnabled)
            Text("Light checks for photos and screens. Heavy also requires a blink or a small head turn. Protected in-app actions keep their prompted check.")
                .font(.caption).foregroundStyle(.secondary)
            if !preferences.options.livenessEnabled { Label("Automatic unlocking paused", systemImage: "pause.circle").foregroundStyle(.orange) }
            Text("A camera check cannot guarantee protection against every photo or video. It does not provide hardware Face ID or Touch ID security.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
