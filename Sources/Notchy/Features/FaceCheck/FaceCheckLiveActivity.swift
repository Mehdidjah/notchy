import Combine
import SwiftUI

/// A small pill, a native scan below the camera, and a held result. No media decoding or
/// frame-driven model updates are needed for the animation.
@MainActor
final class FaceCheckLiveActivity: ObservableObject, ClosedLiveActivity {
    enum Phase: Equatable, Sendable { case hidden, preparing, scanning, saved, recognized, failed }

    static let expansionDelay: Duration = .milliseconds(160)
    static let successHold: Duration = .milliseconds(1_700)
    static let failureHold: Duration = .seconds(5)

    let activityID = "faceCheck"
    let priority = ClosedActivityPriority.faceCheck
    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var prompt = "Look at the camera"
    @Published private(set) var reason = "Face Check"
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?
    var onExpired: (() -> Void)?
    var hapticsEnabled: () -> Bool = { true }
    private let haptics: HapticFeedbackPerforming
    private let changes = PassthroughSubject<Void, Never>()
    private var transition: Task<Void, Never>?
    private var sequence = 0
    private var wasHovering = false

    init(haptics: HapticFeedbackPerforming = SystemHapticFeedback()) { self.haptics = haptics }
    var isActivityVisible: Bool { phase != .hidden }
    var suppressesAutomaticOpen: Bool { isActivityVisible }
    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func begin(reason: String) {
        wasHovering = false
        sequence &+= 1
        let current = sequence
        transition?.cancel()
        self.reason = reason
        prompt = "Look at the camera"
        setPhase(.preparing)
        transition = Task { [weak self] in
            try? await Task.sleep(for: Self.expansionDelay)
            guard !Task.isCancelled, let self, self.sequence == current else { return }
            self.setPhase(.scanning)
        }
    }

    func update(prompt: String) {
        guard self.prompt != prompt else { return }
        self.prompt = prompt
    }

    func finish(saved: Bool = false, recognized: Bool, message: String) {
        sequence &+= 1
        let current = sequence
        transition?.cancel()
        prompt = message
        setPhase(saved ? .saved : (recognized ? .recognized : .failed))
        if hapticsEnabled() { haptics.perform() }
        transition = Task { [weak self] in
            try? await Task.sleep(for: recognized || saved ? Self.successHold : Self.failureHold)
            guard !Task.isCancelled, let self, self.sequence == current else { return }
            self.dismiss()
            self.onExpired?()
        }
    }

    func dismiss() {
        wasHovering = false
        sequence &+= 1
        transition?.cancel()
        transition = nil
        setPhase(.hidden)
    }

    @discardableResult func handleHover(_ hovering: Bool) -> Bool {
        let entered = hovering && !wasHovering
        wasHovering = hovering
        guard isActivityVisible else { return false }
        if entered, phase == .failed { onRetry?() }
        return true
    }

    @discardableResult func handleTap() -> Bool {
        isActivityVisible
    }

    func retry() { if phase == .failed { onRetry?() } }
    func cancel() { onCancel?() }

    private func setPhase(_ next: Phase) {
        guard phase != next else { return }
        phase = next
        changes.send()
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat { 0 }
    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat { 0 }
    func leftWing(in context: ClosedActivityContext) -> AnyView { AnyView(Color.clear) }
    func rightWing(in context: ClosedActivityContext) -> AnyView { AnyView(Color.clear) }
    func layout(in context: ClosedActivityContext) -> ClosedActivityLayout {
        let expanded = phase != .preparing && phase != .hidden
        let hover: CGFloat = context.isHovering ? 6 : 0
        let padding = NotchSilhouette.closedHorizontalPadding * 2
        let width: CGFloat
        let height: CGFloat
        if context.hasHardwareNotch {
            width = expanded ? max(252, context.notchWidth + 32) : context.notchWidth + padding
            height = expanded ? max(200, context.closedHeight + 164) : context.closedHeight
        } else {
            width = expanded ? 180 : 80
            height = expanded ? 180 : 24
        }
        return ClosedActivityLayout(
            leftWidth: 0, centerWidth: width + hover - padding,
            rightWidth: 0, contentHeight: context.contentHeight,
            outerHeight: height + hover
        )
    }
    func expandedContent(in context: ClosedActivityContext) -> AnyView? {
        guard phase != .preparing && phase != .hidden else { return nil }
        let topInset = context.hasHardwareNotch ? context.closedHeight : 8
        return AnyView(VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            FaceCheckActivityView(activity: self, emblemSize: context.hasHardwareNotch ? 140 : 116)
                .frame(height: layout(in: context).outerHeight - topInset)
        })
    }
}

struct FaceCheckActivityView: View {
    @ObservedObject var activity: FaceCheckLiveActivity
    var animates = true
    var emblemSize: CGFloat = 140
    private var succeeded: Bool { activity.phase == .saved || activity.phase == .recognized }

    var body: some View {
        VStack(spacing: 0) {
            FaceCheckEmblem(phase: activity.phase, animates: animates)
                .id(activity.phase)
                .frame(width: emblemSize, height: emblemSize)
                .accessibilityHidden(true)
            Group {
                if succeeded {
                    Text(activity.phase == .saved ? "Face saved" : "Recognized")
                } else if activity.phase == .failed {
                    Button("Hover to retry") { activity.retry() }
                        .buttonStyle(.plain)
                        .help(activity.prompt)
                } else {
                    Text(activity.prompt)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(height: 24)
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if !succeeded {
                Button { activity.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel Face Check")
                .help("Cancel Face Check (Escape)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(activity.reason). \(activity.prompt)")
        .help(activity.reason)
        .onHover { activity.handleHover($0) }
        .onExitCommand { activity.cancel() }
    }
}
