import SwiftUI

/// Onboarding rows for the Settings window. Returns a `Section`, so embed it in a `Form`.
struct OnboardingSettingsSection: View {
    @ObservedObject private var settings: OnboardingSettings
    @ObservedObject private var hello: OnboardingHelloController

    init(settings: OnboardingSettings = .shared, hello: OnboardingHelloController = .shared) {
        _settings = ObservedObject(wrappedValue: settings)
        _hello = ObservedObject(wrappedValue: hello)
    }

    var body: some View {
        Section("Onboarding") {
            LabeledContent("Status") {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            Button("Show onboarding again") {
                OnboardingFeature.showOnboardingAgain()
            }
            Button("Replay hello animation") {
                OnboardingFeature.replayHello()
            }
            .disabled(hello.isPresenting)
            Toggle("Play welcome sound with the first-launch hello", isOn: $settings.playsWelcomeSound)
            Button("Run onboarding again at next launch") {
                settings.resetForNextLaunch()
            }
            .disabled(!settings.completed && !settings.helloShown)
            Text("The onboarding walks through the notch gestures, permissions, your music app and which features to turn on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        guard settings.completed else { return "Not finished" }
        if let date = settings.completedAt {
            return "Completed \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Completed"
    }
}
