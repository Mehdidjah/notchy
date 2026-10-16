import SwiftUI

/// One of the two hardware indicators the privacy activity can show.
enum PrivacyIndicatorKind: String, CaseIterable, Sendable {
    case camera
    case microphone

    var systemImage: String {
        switch self {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        }
    }

    /// Camera green #26CC41 and microphone orange #FF9402, the system's own indicator colours.
    var tint: Color {
        switch self {
        case .camera: Color(red: 0.152, green: 0.804, blue: 0.256)
        case .microphone: Color(red: 1.000, green: 0.584, blue: 0.010)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .camera: "Camera in use"
        case .microphone: "Microphone in use"
        }
    }
}

/// What the privacy activity shows, after the user's detection switches are applied.
///
/// Atoll distinguishes eight combinations of camera, microphone and screen recording. They
/// reduce to two questions: what sits in the left wing, and which glyphs sit in the right one.
struct PrivacyIndicatorState: Equatable, Sendable {
    var camera: Bool
    var microphone: Bool
    var screenRecording: Bool

    static let none = PrivacyIndicatorState(camera: false, microphone: false, screenRecording: false)

    var hasAnyIndicator: Bool { camera || microphone || screenRecording }

    /// Content of the left wing.
    enum LeftContent: Equatable, Sendable {
        case empty
        /// The red pulsing dot of a screen recording.
        case recordingBadge
        /// The microphone moves left when both devices are live and nothing is recording.
        case microphone
    }

    var leftContent: LeftContent {
        if screenRecording { return .recordingBadge }
        if camera && microphone { return .microphone }
        return .empty
    }

    /// Glyphs in the right wing, leading to trailing.
    var rightIndicators: [PrivacyIndicatorKind] {
        if camera && microphone {
            return screenRecording ? [.microphone, .camera] : [.camera]
        }
        var kinds: [PrivacyIndicatorKind] = []
        if microphone { kinds.append(.microphone) }
        if camera { kinds.append(.camera) }
        return kinds
    }

    /// Left wing width: the square wing plus 20 pt when it has content, otherwise nothing.
    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        leftContent == .empty ? 0 : PrivacyIndicatorState.wingWidth(closedHeight: context.closedHeight)
    }

    /// Right wing width: always the square wing plus 20 pt while the activity shows.
    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        PrivacyIndicatorState.wingWidth(closedHeight: context.closedHeight)
    }

    /// Extra width Atoll gives each privacy wing beyond the square content height.
    static let wingExtra: CGFloat = 20

    /// One non-empty privacy wing: the resting content height (notch height less 12) plus
    /// 20 pt. Atoll's privacy view keeps its own hover and swipe state, which never changes,
    /// so its wings do not swell when the pointer is on the island or during a swipe.
    static func wingWidth(closedHeight: CGFloat) -> CGFloat {
        max(0, closedHeight - 12) + wingExtra
    }

    var accessibilityDescription: String {
        var parts: [String] = []
        if camera { parts.append("camera") }
        if microphone { parts.append("microphone") }
        if screenRecording { parts.append("screen recording") }
        guard !parts.isEmpty else { return "No privacy indicators" }
        return "In use: " + parts.joined(separator: ", ")
    }
}
