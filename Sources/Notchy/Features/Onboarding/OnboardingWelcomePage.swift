import SwiftUI

/// First page: a spotlight over a sparkle field, the app mark, name and "Welcome", a
/// "Get started" button, the privacy link, and a wordmark near the bottom, all on a dark
/// HUD-window blur (Atoll's WelcomeView).
struct OnboardingWelcomePage: View {
    var onGetStarted: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                OnboardingSpotlight()
                    .padding(.bottom)
                    .blur(radius: 3)
                    .offset(y: -5)
                    .background(OnboardingSparkleField().opacity(0.6))

                VStack(spacing: 8) {
                    OnboardingAppGlyph(size: 100)
                        .padding(.bottom, 8)
                    Text("Notchy")
                        .font(.system(.largeTitle, design: .default))
                        .fontWeight(.semibold)
                    Text("Welcome")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 30)

                    Button(action: onGetStarted) {
                        Text("Get started")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)

                    OnboardingPrivacyLink()
                        .padding(.top, 8)
                }
                .padding(.top)
            }

            OnboardingWordmark()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding()
                .padding(.bottom, 36)
                .blendMode(.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background {
            OnboardingVisualEffect(material: .hudWindow)
                .ignoresSafeArea()
        }
    }
}
