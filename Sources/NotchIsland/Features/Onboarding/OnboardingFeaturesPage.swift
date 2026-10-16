import SwiftUI

/// One switch on the feature page.
struct OnboardingFeatureToggle: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let keyPath: WritableKeyPath<OnboardingFeatureChoices, Bool>
    var isLocked = false

    @MainActor static let all: [OnboardingFeatureToggle] = [
        OnboardingFeatureToggle(id: "clipboard", title: "Clipboard History", detail: "Everything you copy. Always on.", systemImage: "doc.on.clipboard", tint: .gray, keyPath: \.clipboard, isLocked: true),
        OnboardingFeatureToggle(id: "shelf", title: "Shelf", detail: "Drop files on the notch to keep them handy.", systemImage: "tray.fill", tint: .blue, keyPath: \.shelf),
        OnboardingFeatureToggle(id: "calendar", title: "Calendar", detail: "Today's events next to your music.", systemImage: "calendar", tint: .red, keyPath: \.calendar),
        OnboardingFeatureToggle(id: "mirror", title: "Camera Mirror", detail: "A quick look at yourself before a call.", systemImage: "camera.fill", tint: .teal, keyPath: \.mirror),
        OnboardingFeatureToggle(id: "timer", title: "Timer", detail: "Countdowns that live in the notch.", systemImage: "timer", tint: .orange, keyPath: \.timer),
        OnboardingFeatureToggle(id: "stats", title: "System Stats", detail: "CPU, memory, network and disk at a glance.", systemImage: "chart.xyaxis.line", tint: .green, keyPath: \.stats),
        OnboardingFeatureToggle(id: "notes", title: "Notes", detail: "Jot something down without leaving your app.", systemImage: "note.text", tint: .yellow, keyPath: \.notes),
        OnboardingFeatureToggle(id: "colorPicker", title: "Color Picker", detail: "Sample any pixel and copy its color.", systemImage: "eyedropper", tint: .pink, keyPath: \.colorPicker),
        OnboardingFeatureToggle(id: "inlineHUD", title: "Inline HUD", detail: "Volume and brightness grow out of the notch sideways.", systemImage: "speaker.wave.2.fill", tint: .purple, keyPath: \.inlineHUD),
        OnboardingFeatureToggle(id: "haptics", title: "Haptic Feedback", detail: "A gentle tap when the notch opens.", systemImage: "hand.tap.fill", tint: .indigo, keyPath: \.haptics)
    ]
}

/// "Pick Your Features": the switches the profiles chose, ready to adjust before finishing.
struct OnboardingFeaturesPage: View {
    @ObservedObject var flow: OnboardingFlowModel
    let onContinue: () -> Void

    var body: some View {
        // Same header and Continue button as the profile page (Atoll's constants).
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "switch.2")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.bottom, 8)

                Text("Pick Your Features")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("These match your profile. Change anything now, or later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(OnboardingFeatureToggle.all.enumerated()), id: \.element.id) { index, feature in
                        if index > 0 {
                            Divider().padding(.leading, 50)
                        }
                        row(for: feature)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal, 24)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingPageBackground()
    }

    private func row(for feature: OnboardingFeatureToggle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(feature.tint.gradient))

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.body)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle(feature.title, isOn: binding(for: feature))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(feature.isLocked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func binding(for feature: OnboardingFeatureToggle) -> Binding<Bool> {
        Binding(
            get: { flow.featureChoices[keyPath: feature.keyPath] },
            set: { newValue in
                guard !feature.isLocked else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    flow.featureChoices[keyPath: feature.keyPath] = newValue
                }
            }
        )
    }
}
