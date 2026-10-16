import Combine
import Foundation

/// The pages of the onboarding window, in order.
///
/// Atoll's six pages are welcome, camera, calendar, music source, profile and finished.
/// NotchIsland adds a page that teaches the notch gestures, an Accessibility page (pasting
/// and media keys need it), Automation inside the music page, and a feature-toggle page after
/// the profiles.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case gestures
    case accessibility
    case camera
    case calendar
    case musicSource
    case profile
    case features
    case finished

    var id: Int { rawValue }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// The permission a page asks for, if it is a permission page.
    var permission: OnboardingPermission? {
        switch self {
        case .accessibility: .accessibility
        case .camera: .camera
        case .calendar: .calendar
        default: nil
        }
    }
}

/// Page state for the onboarding window.
@MainActor
final class OnboardingFlowModel: ObservableObject {
    @Published private(set) var step: OnboardingStep
    /// Profiles ticked on the profile page.
    @Published var selectedProfiles: Set<OnboardingProfile>
    /// Feature switches shown on the feature page, seeded from the profiles.
    @Published var featureChoices: OnboardingFeatureChoices
    @Published var musicSource: OnboardingMusicSource

    private let baseChoices: OnboardingFeatureChoices

    init(
        step: OnboardingStep = .welcome,
        selectedProfiles: Set<OnboardingProfile> = [],
        musicSource: OnboardingMusicSource = .defaultSource,
        baseChoices: OnboardingFeatureChoices = .atollDefaults
    ) {
        self.step = step
        self.selectedProfiles = selectedProfiles
        self.musicSource = musicSource
        self.baseChoices = baseChoices
        featureChoices = baseChoices
    }

    var canContinueFromProfiles: Bool { !selectedProfiles.isEmpty }

    func toggle(_ profile: OnboardingProfile) {
        if selectedProfiles.contains(profile) {
            selectedProfiles.remove(profile)
        } else {
            selectedProfiles.insert(profile)
        }
    }

    /// Moves to the next page. Leaving the profile page seeds the feature switches.
    func advance() {
        guard let next = step.next else { return }
        if step == .profile {
            featureChoices = OnboardingFeatureChoices.resolved(for: selectedProfiles, base: baseChoices)
        }
        step = next
    }

    func go(to step: OnboardingStep) {
        self.step = step
    }
}
