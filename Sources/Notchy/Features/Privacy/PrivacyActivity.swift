import Combine
import SwiftUI

/// What the privacy wings draw. Updated only while something is live, so the glyphs stay put
/// while the island folds the activity away instead of blinking out a frame early.
@MainActor
final class PrivacyWingModel: ObservableObject {
    @Published fileprivate(set) var displayed: PrivacyIndicatorState = .none
}

/// Camera and microphone indicators on the closed notch.
///
/// Right wing: the green camera and/or orange microphone glyphs, trailing. Left wing: empty
/// and zero-wide for a single device; the microphone when both devices are live; the red
/// pulsing badge when a screen recording is reported. Each non-empty wing is the square wing
/// plus 20 pt.
@MainActor
final class PrivacyActivity: ClosedLiveActivity {
    static let identifier = "privacy"

    let activityID = PrivacyActivity.identifier
    let priority = ClosedActivityPriority.privacy
    /// The registry to re-run inside an animation when only the wing widths change.
    weak var center: IslandActivityCenter?

    let wingModel = PrivacyWingModel()
    private(set) var state: PrivacyIndicatorState
    private(set) var detectionEnabled: Bool
    private let changes = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: PrivacyMonitor = .shared) {
        state = monitor.indicators
        detectionEnabled = monitor.settings.anyDetectionEnabled
        if state.hasAnyIndicator { wingModel.displayed = state }

        monitor.$indicators
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] next in self?.update(state: next) }
            .store(in: &cancellables)
        monitor.settings.$enableCameraDetection
            .combineLatest(monitor.settings.$enableMicrophoneDetection)
            .map { $0 || $1 }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in self?.update(detectionEnabled: enabled) }
            .store(in: &cancellables)
    }

    var isActivityVisible: Bool { detectionEnabled && state.hasAnyIndicator }

    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        state.leftWingWidth(in: context)
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        state.rightWingWidth(in: context)
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(PrivacyLeftWing(model: wingModel, closedHeight: context.closedHeight))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(PrivacyRightWing(model: wingModel))
    }

    // MARK: - Updates

    private func update(state next: PrivacyIndicatorState? = nil, detectionEnabled enabled: Bool? = nil) {
        let wasVisible = isActivityVisible
        let hadLeftWing = state.leftContent != .empty
        if let next { state = next }
        if let enabled { detectionEnabled = enabled }

        if state.hasAnyIndicator, wingModel.displayed != state {
            withAnimation(.smooth(duration: 0.4)) { wingModel.displayed = state }
        }

        let visibilityChanged = wasVisible != isActivityVisible
        let widthChanged = hadLeftWing != (state.leftContent != .empty)
        guard visibilityChanged || widthChanged else { return }
        if !visibilityChanged {
            // Same activity, new wing widths: let the island grow or shrink over 0.4 s.
            withAnimation(.smooth(duration: 0.4)) { center?.reevaluate() }
        }
        changes.send()
    }
}

// MARK: - Wings

private struct PrivacyLeftWing: View {
    @ObservedObject var model: PrivacyWingModel
    let closedHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            switch model.displayed.leftContent {
            case .recordingBadge:
                PrivacyRecordingBadge(side: max(0, closedHeight - 12))
            case .microphone:
                PrivacyGlyph(kind: .microphone)
            case .empty:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}

private struct PrivacyRightWing: View {
    @ObservedObject var model: PrivacyWingModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.displayed.rightIndicators, id: \.self) { kind in
                PrivacyGlyph(kind: kind)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.displayed.accessibilityDescription)
    }
}

/// A camera or microphone glyph: 13-pt semibold in a 24-pt square, in the indicator colour.
struct PrivacyGlyph: View {
    let kind: PrivacyIndicatorKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind.tint)
            .frame(width: 24, height: 24)
            .accessibilityLabel(kind.accessibilityLabel)
    }
}

/// The red recording badge: a faint red rounded square with a 10-pt dot that pulses.
private struct PrivacyRecordingBadge: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.15))
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .modifier(PrivacyPulse())
        }
        .frame(width: side, height: side)
    }
}

/// Grows to 1.2x and dims to 70 % and back, 0.8 s each way, forever.
private struct PrivacyPulse: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1)
            .opacity(isPulsing ? 0.7 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
