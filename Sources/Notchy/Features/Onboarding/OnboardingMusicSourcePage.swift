import SwiftUI

/// "Choose a Music Source": radio cards for the music apps. The selected card also shows the app's live Automation
/// status and a button that asks macOS for permission to control it.
struct OnboardingMusicSourcePage: View {
    @ObservedObject var flow: OnboardingFlowModel
    @ObservedObject var permissions: OnboardingPermissionCenter
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Music Source")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Select the music source you want to use. You can change this later in the app settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(OnboardingMusicSource.allCases) { source in
                        OnboardingMusicSourceCard(
                            source: source,
                            isSelected: flow.musicSource == source,
                            permissions: permissions,
                            onSelect: {
                                withAnimation(OnboardingMusicSourceCard.selectionSpring) {
                                    flow.musicSource = source
                                }
                            }
                        )
                    }

                    Text("macOS asks once per app before Notchy can read what is playing and control playback. If the app is closed, Notchy opens it in the background to ask.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding()
            }

            Spacer()

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingPageBackground()
    }
}

struct OnboardingMusicSourceCard: View {
    /// Radio-button spring.
    static let selectionSpring = Animation.spring(response: 0.3, dampingFraction: 0.6)

    let source: OnboardingMusicSource
    let isSelected: Bool
    @ObservedObject var permissions: OnboardingPermissionCenter
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                .animation(Self.selectionSpring, value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(source.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isSelected {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(source.automationPermissions) { permission in
                            automationRow(for: permission)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func automationRow(for permission: OnboardingPermission) -> some View {
        let status = permissions.status(of: permission)
        let isRequesting = permissions.requestsInFlight.contains(permission)
        // One app: "Automation: …"; Automatic lists each app by name.
        let prefix = source.automationPermissions.count > 1
            ? (permission.automationTargetName ?? "Automation")
            : "Automation"
        let request = { Task { @MainActor in await permissions.request(permission) } }
        return HStack(spacing: 8) {
            OnboardingStatusPill(status: status, isBusy: isRequesting, prefix: prefix, compact: true)
            Spacer(minLength: 0)
            switch status {
            case .notDetermined, .targetNotRunning:
                Button("Allow Control") { _ = request() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRequesting)
            case .denied, .restricted:
                Button("Open Settings") { _ = request() }
                    .buttonStyle(.link)
                    .controlSize(.small)
            case .granted, .targetNotInstalled:
                EmptyView()
            }
        }
    }
}
