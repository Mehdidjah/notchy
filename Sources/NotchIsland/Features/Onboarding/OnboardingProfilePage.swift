import SwiftUI

/// "Choose Your Profile": a two-column grid of multi-select profile cards; Continue stays
/// disabled until at least one is picked (Atoll's ProfileSelectionView).
struct OnboardingProfilePage: View {
    @ObservedObject var flow: OnboardingFlowModel
    let onContinue: () -> Void

    var body: some View {
        // Atoll's constants throughout: 50-pt glyph with 8 pt under it, 20 pt above the header,
        // 24 pt between header and grid, a Continue button with 12-pt vertical padding and a
        // 24-pt margin. In Atoll that stack (with 24 + spacer + 24 above Continue) is taller
        // than the 600-pt page, so it rides up under the transparent title bar and the button
        // is clipped at the bottom. Here the page uses the title-bar inset on purpose and the
        // gap above Continue is flexible, so the header sits where Atoll's does and the button
        // keeps its full 24-pt margin.
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.bottom, 8)

                Text("Choose Your Profile")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Select one or more profiles to customize your experience")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(OnboardingProfile.allCases) { profile in
                    OnboardingProfileCard(
                        profile: profile,
                        isSelected: flow.selectedProfiles.contains(profile)
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            flow.toggle(profile)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer(minLength: 0)

            Button {
                if flow.canContinueFromProfiles { onContinue() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!flow.canContinueFromProfiles)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .onboardingPageBackground()
    }
}

struct OnboardingProfileCard: View {
    let profile: OnboardingProfile
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        let accent = LinearGradient(colors: profile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: profile.systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(accent)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(profile.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(height: 160)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: profile.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? accent : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom), lineWidth: isSelected ? 2 : 0)
            )
            .scaleEffect(isHovering ? 1.02 : 1)
            .shadow(color: isSelected ? profile.gradient[0].opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
