import SwiftUI

/// A permission page: a large accent glyph, title, explanation, privacy note and the buttons
/// (Atoll's PermissionRequestView). Once the permission has an answer, a status pill above
/// the buttons reports it.
///
/// - Not asked yet: "Not Now" and "Allow Access", which shows the system prompt; exactly
///   Atoll's page, with no status pill.
/// - Denied or restricted: "Not Now" and "Open System Settings", since macOS will not ask again.
/// - Allowed: "Continue".
struct OnboardingPermissionPage: View {
    let permission: OnboardingPermission
    let systemImage: String
    let title: String
    let description: String
    let privacyNote: String?
    /// Camera and Calendar move on as soon as the system prompt is answered, like Atoll.
    /// Accessibility stays so the user can come back from System Settings.
    let advancesAfterPrompt: Bool
    @ObservedObject var permissions: OnboardingPermissionCenter
    let onContinue: () -> Void

    var body: some View {
        let status = permissions.status(of: permission)
        let isRequesting = permissions.requestsInFlight.contains(permission)

        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 32)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text(description)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            if let privacyNote {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                    Text(privacyNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
            }

            VStack(spacing: 14) {
                if status != .notDetermined || isRequesting {
                    OnboardingStatusPill(status: status, isBusy: isRequesting)
                        .transition(.opacity)
                }
                buttons(for: status, isRequesting: isRequesting)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onboardingPageBackground()
        .animation(.smooth(duration: 0.25), value: status)
    }

    @ViewBuilder
    private func buttons(for status: OnboardingPermissionStatus, isRequesting: Bool) -> some View {
        HStack {
            if status.isGranted {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Not Now", action: onContinue)
                    .buttonStyle(.bordered)
                if status == .denied || status == .restricted {
                    Button("Open System Settings") {
                        permissions.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Allow Access") {
                        Task { @MainActor in
                            await permissions.request(permission)
                            if advancesAfterPrompt { onContinue() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting)
                }
            }
        }
    }
}

/// A small capsule with a coloured dot and the permission's current status.
struct OnboardingStatusPill: View {
    let status: OnboardingPermissionStatus
    var isBusy = false
    var prefix: String?
    /// Smaller type and padding, for use inside cards.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(status.tint)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
            }
            Text(text)
                .font(compact ? .caption : .callout)
                .fontWeight(.medium)
                .foregroundStyle(status.isGranted ? Color.primary : Color.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .fixedSize()
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(status.tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        let label = compact ? status.shortLabel : status.label
        return prefix.map { "\($0): \(label)" } ?? label
    }
}
