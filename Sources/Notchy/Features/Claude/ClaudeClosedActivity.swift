import Combine
import SwiftUI

/// Claude on the closed notch: Claude Code's mark on the left, and on the right three dots
/// while Claude works or a green dot while a session waits for the user (a number when there
/// are several). When a session should be compacted soon or a plan limit is running out, the
/// right side shows that instead: a ring and its percentage, orange, or red once it's urgent.
/// While Claude works it comes after music and before the timer; a session that is only open
/// sits at the back of the chain, so it never hides anything else.
@MainActor
final class ClaudeClosedActivity: ClosedLiveActivity {
    static let id = "claude"
    /// While Claude works: after music, before the timer.
    static let workingPriority = 45
    /// While a session only waits: behind everything else but the shelf.
    static let waitingPriority = 120

    let activityID = ClaudeClosedActivity.id
    /// Called when the closed notch is clicked while Claude is shown.
    var onTap: (() -> Void)?

    private let monitor: ClaudeLiveMonitor
    private let settings: ClaudeSettings
    private let attention: ClaudeAttention

    init(monitor: ClaudeLiveMonitor = .shared, settings: ClaudeSettings = .shared, attention: ClaudeAttention = .shared) {
        self.monitor = monitor
        self.settings = settings
        self.attention = attention
    }

    var priority: Int { monitor.snapshot.isWorking ? Self.workingPriority : Self.waitingPriority }

    var isActivityVisible: Bool {
        Self.isVisible(snapshot: monitor.snapshot, mode: settings.closedNotch)
    }

    static func isVisible(snapshot: ClaudeLiveSnapshot, mode: ClaudeClosedNotchMode) -> Bool {
        switch mode {
        case .whileOpen: snapshot.isWorking || snapshot.openCount > 0
        case .whileWorking: snapshot.isWorking
        case .never: false
        }
    }

    /// Re-evaluates the chain only when what it depends on changes: whether Claude shows,
    /// whether it is working (its priority), and whether an alert widens the right wing. The
    /// wing views follow the monitor and the alerts themselves.
    var activityDidChange: AnyPublisher<Void, Never> {
        monitor.$snapshot.combineLatest(settings.$closedNotch, attention.$alerts)
            .map { snapshot, mode, alerts in
                VisibilityKey(
                    isVisible: Self.isVisible(snapshot: snapshot, mode: mode),
                    isWorking: snapshot.isWorking,
                    showsAlert: !alerts.isEmpty
                )
            }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private struct VisibilityKey: Equatable {
        let isVisible: Bool
        let isWorking: Bool
        let showsAlert: Bool
    }

    /// Room for the ring and "100%" while an alert shows.
    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        guard attention.top != nil else { return context.wingBaseWidth }
        return Self.alertWingWidth(height: context.contentHeight) + max(0, context.gestureProgress) / 2
    }

    static func alertWingWidth(height: CGFloat) -> CGFloat {
        (height * 0.6).rounded() + 34
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ClaudeClosedLogoWing(monitor: monitor, height: context.contentHeight))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ClaudeClosedStatusWing(monitor: monitor, attention: attention, height: context.contentHeight))
    }

    @discardableResult func handleTap() -> Bool {
        guard isActivityVisible else { return false }
        onTap?()
        // The click still opens the island, now on the Claude tab.
        return false
    }
}

/// Claude Code's mark, hopping gently while Claude works.
private struct ClaudeClosedLogoWing: View {
    @ObservedObject var monitor: ClaudeLiveMonitor
    let height: CGFloat
    @State private var isUp = false

    var body: some View {
        let isWorking = monitor.snapshot.isWorking
        ClaudeCodeLogo()
            .frame(width: max(0, height * 0.95), height: max(0, height * 0.6))
            .offset(y: isWorking && isUp ? -height * 0.08 : 0)
            .animation(
                isWorking ? .easeInOut(duration: 0.42).repeatForever(autoreverses: true) : .smooth(duration: 0.2),
                value: isWorking && isUp
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { isUp = true }
            .accessibilityElement()
            .accessibilityLabel(isWorking ? "Claude is working" : "Claude Code session open")
    }
}

/// Three dots while Claude works, a green dot while a session waits; a number for several.
/// An alert takes their place.
private struct ClaudeClosedStatusWing: View {
    @ObservedObject var monitor: ClaudeLiveMonitor
    @ObservedObject var attention: ClaudeAttention
    let height: CGFloat

    var body: some View {
        let snapshot = monitor.snapshot
        Group {
            if let alert = attention.top {
                ClaudeAlertGauge(alert: alert, height: height)
            } else if snapshot.isWorking {
                if snapshot.workingCount > 1 {
                    count(snapshot.workingCount, color: ClaudeMark.orange)
                } else {
                    ClaudeWorkingDots(dot: max(2, height * 0.16))
                }
            } else if snapshot.openCount > 1 {
                count(snapshot.openCount, color: Color.green)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: max(3, height * 0.3), height: max(3, height * 0.3))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: snapshot.isWorking)
        .animation(.smooth(duration: 0.2), value: attention.top?.subject)
        .accessibilityElement()
        .accessibilityLabel(attention.top.map(ClaudeAlertGauge.label) ?? label(snapshot))
    }

    private func count(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(.system(size: max(8, height * 0.6), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }

    private func label(_ snapshot: ClaudeLiveSnapshot) -> String {
        if snapshot.isWorking {
            return snapshot.workingCount == 1 ? "Claude is working" : "Claude is working in \(snapshot.workingCount) sessions"
        }
        return snapshot.openCount == 1 ? "A session is waiting for you" : "\(snapshot.openCount) sessions waiting for you"
    }
}

/// Three orange dots that light up in turn.
private struct ClaudeWorkingDots: View {
    let dot: CGFloat
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: dot * 0.7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ClaudeMark.orange)
                    .frame(width: dot, height: dot)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.17),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}

/// A ring filled to the alert's percentage, with the number beside it.
private struct ClaudeAlertGauge: View {
    let alert: ClaudeAlert
    let height: CGFloat

    var body: some View {
        let color = alert.level == .critical ? Color.red : Color.orange
        let ring = (height * 0.6).rounded()
        HStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: alert.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: ring, height: ring)
            Text("\(alert.percent)%")
                .font(.system(size: max(8, height * 0.55), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
    }

    static func label(_ alert: ClaudeAlert) -> String {
        switch alert.subject {
        case .context:
            "Context \(alert.percent) percent full in \(alert.project ?? "a session"), compact it soon"
        case .limit(let kind):
            "\(kind == .session ? "Session" : "Weekly") limit \(alert.percent) percent used"
        }
    }
}
