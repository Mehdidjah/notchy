import SwiftUI

/// Last page: sparkles, "You're All Set!", and the way out: Customize in Settings, or Finish
/// (the default button). Atoll's OnboardingFinishView.
struct OnboardingFinishPage: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .padding()

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("You can now enjoy the app. If you want to tweak things further, you can always visit the settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()

            VStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Label("Customize in Settings", systemImage: "gear")
                }
                .controlSize(.large)

                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                OnboardingPrivacyLink()
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingPageBackground()
    }
}
