import SwiftUI

/// The onboarding window's content: one page at a time, cross-fading between pages over
/// 0.6 s with an ease-in-out curve, in a fixed 400 x 600 frame (Atoll's OnboardingView).
/// When it first appears it asks, once, how Focus should be detected.
struct OnboardingView: View {
    @ObservedObject var flow: OnboardingFlowModel
    @ObservedObject var permissions: OnboardingPermissionCenter
    let onMusicSourceChosen: (OnboardingMusicSource) -> Void
    let onFeaturesChosen: (Set<OnboardingProfile>, OnboardingFeatureChoices) -> Void
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    /// Saves the Focus detection answer; nil skips the question.
    var onFocusDetectionModeChosen: ((OnboardingFocusDetectionMode) -> Void)? = nil

    @State private var isAskingFocusDetectionMode = false
    @State private var didAskFocusDetectionMode = false

    static let pageTransition = Animation.easeInOut(duration: 0.6)
    static let windowSize = CGSize(width: 400, height: 600)

    var body: some View {
        ZStack {
            switch flow.step {
            case .welcome:
                OnboardingWelcomePage(onGetStarted: advance)
                    .transition(.opacity)

            case .gestures:
                OnboardingGesturesPage(onContinue: advance)
                    .transition(.opacity)

            case .accessibility:
                OnboardingPermissionPage(
                    permission: .accessibility,
                    systemImage: "accessibility",
                    title: "Enable Accessibility Access",
                    description: "Notchy pastes clipboard items straight into the app you are working in and reacts to the volume, brightness and media keys to show its HUDs. macOS asks for Accessibility access before an app can do either.",
                    privacyNote: "Notchy only sends the paste you ask for and never records what you type.",
                    advancesAfterPrompt: false,
                    permissions: permissions,
                    onContinue: advance
                )
                .transition(.opacity)

            case .camera:
                OnboardingPermissionPage(
                    permission: .camera,
                    systemImage: "camera.fill",
                    title: "Enable Camera Access",
                    description: "Notchy includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    advancesAfterPrompt: true,
                    permissions: permissions,
                    onContinue: advance
                )
                .transition(.opacity)

            case .calendar:
                OnboardingPermissionPage(
                    permission: .calendar,
                    systemImage: "calendar",
                    title: "Enable Calendar Access",
                    description: "Notchy can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    advancesAfterPrompt: true,
                    permissions: permissions,
                    onContinue: advance
                )
                .transition(.opacity)

            case .musicSource:
                OnboardingMusicSourcePage(flow: flow, permissions: permissions) {
                    onMusicSourceChosen(flow.musicSource)
                    advance()
                }
                .transition(.opacity)

            case .profile:
                OnboardingProfilePage(flow: flow, onContinue: advance)
                    .transition(.opacity)

            case .features:
                OnboardingFeaturesPage(flow: flow) {
                    onFeaturesChosen(flow.selectedProfiles, flow.featureChoices)
                    advance()
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishPage(onFinish: onFinish, onOpenSettings: onOpenSettings)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear {
            guard onFocusDetectionModeChosen != nil, !didAskFocusDetectionMode else { return }
            didAskFocusDetectionMode = true
            isAskingFocusDetectionMode = true
        }
        .confirmationDialog(
            "Focus detection mode",
            isPresented: $isAskingFocusDetectionMode,
            titleVisibility: .visible
        ) {
            ForEach(OnboardingFocusDetectionMode.allCases, id: \.self) { mode in
                Button(mode.title) { onFocusDetectionModeChosen?(mode) }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("This is optional. You can change it any time in Settings.")
        }
    }

    private func advance() {
        withAnimation(Self.pageTransition) {
            flow.advance()
        }
    }
}

/// "Privacy Policy" caption link. Notchy has no hosted policy, so it opens a short
/// statement in a popover instead of a web page.
struct OnboardingPrivacyLink: View {
    @State private var isShowingPolicy = false

    var body: some View {
        Button {
            isShowingPolicy.toggle()
        } label: {
            Text("Privacy Policy")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPolicy, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Your data stays on this Mac", systemImage: "lock.shield")
                    .font(.headline)
                Text("Clipboard history, shelf files, notes, calendar events and camera frames are processed locally and are never uploaded. Notchy has no accounts, analytics or tracking. Each permission can be revoked at any time in System Settings > Privacy & Security.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300)
        }
    }
}
