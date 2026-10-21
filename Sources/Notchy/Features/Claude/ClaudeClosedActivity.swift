import Combine
import SwiftUI

/// Claude on the closed notch: Claude Code's mark on the left, hopping while Claude works, and
/// on the right how full the context of the session the user is in is: a ring and its
/// percentage, orange once it's time to compact and red when Claude Code is about to compact on
/// its own. A plan limit that is about to stop every session takes the ring's place. A session
/// that hasn't replied yet shows three dots while Claude works, a green dot while it waits, or
/// how many sessions are open. While Claude works it comes after music and before the timer; a
/// session that is only open sits at the back of the chain, so it never hides anything else.
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
    /// whether it is working (its priority), and whether the ring widens the right wing. The
    /// wing views follow the monitor and the alerts themselves.
    var activityDidChange: AnyPublisher<Void, Never> {
        monitor.$snapshot.combineLatest(settings.$closedNotch, attention.$alerts)
            .map { snapshot, mode, alerts in
                VisibilityKey(
                    isVisible: Self.isVisible(snapshot: snapshot, mode: mode),
                    isWorking: snapshot.isWorking,
                    showsGauge: Self.gauge(snapshot: snapshot, alerts: alerts, contextWarning: 1) != nil
                )
            }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private struct VisibilityKey: Equatable {
        let isVisible: Bool
        let isWorking: Bool
        let showsGauge: Bool
    }

    /// What the ring shows: a plan limit about to stop every session, or else the context of
    /// the session the user is in. Nil while that session hasn't replied yet.
    static func gauge(snapshot: ClaudeLiveSnapshot, alerts: [ClaudeAlert], contextWarning: Double) -> ClaudeClosedGauge? {
        if let limit = alerts.first(where: { $0.level == .critical && $0.sessionID == nil }) {
            return .limit(limit)
        }
        guard let focus = snapshot.focus, let context = focus.context else { return nil }
        return .context(
            context,
            level: context.level(warningAt: contextWarning),
            project: focus.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        )
    }

    var showsGauge: Bool {
        Self.gauge(snapshot: monitor.snapshot, alerts: attention.alerts, contextWarning: 1) != nil
    }

    /// The island is centred on the screen, so both wings take the ring's width: with one wing
    /// wider than the other, the black centre would slide off the camera housing and cover
    /// part of the ring.
    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        wingWidth(in: context)
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        wingWidth(in: context)
    }

    private func wingWidth(in context: ClosedActivityContext) -> CGFloat {
        guard showsGauge else { return context.wingBaseWidth }
        return ClaudeGaugeMetrics(height: context.contentHeight).wingWidth + max(0, context.gestureProgress) / 2
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ClaudeClosedLogoWing(monitor: monitor, attention: attention, height: context.contentHeight))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ClaudeClosedStatusWing(monitor: monitor, attention: attention, settings: settings, height: context.contentHeight))
    }

    @discardableResult func handleTap() -> Bool {
        guard isActivityVisible else { return false }
        onTap?()
        // The click still opens the island, now on the Claude tab.
        return false
    }
}

/// Sizes of the ring and its percentage at a wing height. The wing is measured for "100%", so
/// the number never runs past it, and keeps the ring clear of the camera housing.
struct ClaudeGaugeMetrics: Equatable {
    /// Between the camera housing and the ring.
    static let notchGap: CGFloat = 8
    /// Between the number and the island's outer edge, mirrored by the logo on the left.
    static let outerPadding: CGFloat = 2
    static let spacing: CGFloat = 3

    let ring: CGFloat
    let fontSize: CGFloat
    /// The widest the number gets: "100%".
    let textWidth: CGFloat

    init(height: CGFloat) {
        ring = (height * 0.6).rounded()
        fontSize = max(8, height * 0.55)
        textWidth = TimerTextMeasurer.width(of: "100%", font: Self.font(size: fontSize)) + 1
    }

    var wingWidth: CGFloat { Self.notchGap + ring + Self.spacing + textWidth + Self.outerPadding }

    /// What the view draws with: the rounded system font, bold, with even-width digits.
    static func font(size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}

/// Claude Code's mark, hopping gently while Claude works. Beside the ring it sits at the outer
/// edge, mirroring the percentage on the right.
private struct ClaudeClosedLogoWing: View {
    @ObservedObject var monitor: ClaudeLiveMonitor
    @ObservedObject var attention: ClaudeAttention
    let height: CGFloat
    @State private var isUp = false

    var body: some View {
        let isWorking = monitor.snapshot.isWorking
        let outward = ClaudeClosedActivity.gauge(snapshot: monitor.snapshot, alerts: attention.alerts, contextWarning: 1) != nil
        ClaudeCodeLogo()
            .frame(width: max(0, height * 0.95), height: max(0, height * 0.6))
            .offset(y: isWorking && isUp ? -height * 0.08 : 0)
            .animation(
                isWorking ? .easeInOut(duration: 0.42).repeatForever(autoreverses: true) : .smooth(duration: 0.2),
                value: isWorking && isUp
            )
            .padding(.leading, outward ? ClaudeGaugeMetrics.outerPadding : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: outward ? .leading : .center)
            .onAppear { isUp = true }
            .accessibilityElement()
            .accessibilityLabel(isWorking ? "Claude is working" : "Claude Code session open")
    }
}

/// What the closed notch's ring shows.
enum ClaudeClosedGauge: Equatable {
    /// How full the context of the session the user is in is.
    case context(ClaudeContextUsage, level: ClaudeUsageLevel, project: String?)
    /// A plan limit about to stop every session.
    case limit(ClaudeAlert)

    var fraction: Double {
        switch self {
        case .context(let context, _, _): context.fraction
        case .limit(let alert): alert.fraction
        }
    }

    var percent: Int {
        switch self {
        case .context(let context, _, _): context.percent
        case .limit(let alert): alert.percent
        }
    }

    var level: ClaudeUsageLevel {
        switch self {
        case .context(_, let level, _): level
        case .limit(let alert): alert.level
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .context(_, let level, let project):
            let advice = switch level {
            case .normal: ""
            case .warning: ", compact it soon"
            case .critical: ", Claude Code is about to compact it"
            }
            return "Context \(percent) percent full in \(project ?? "this session")\(advice)"
        case .limit(let alert):
            return "\(alert.subject == .limit(.session) ? "Session" : "Weekly") limit \(percent) percent used"
        }
    }
}

/// The ring for the session the user is in. Until that session has replied: three dots while
/// Claude works, a green dot while it waits, or how many sessions are open.
private struct ClaudeClosedStatusWing: View {
    @ObservedObject var monitor: ClaudeLiveMonitor
    @ObservedObject var attention: ClaudeAttention
    @ObservedObject var settings: ClaudeSettings
    let height: CGFloat

    var body: some View {
        let snapshot = monitor.snapshot
        let gauge = ClaudeClosedActivity.gauge(
            snapshot: snapshot,
            alerts: attention.alerts,
            contextWarning: Double(settings.contextWarningPercent) / 100
        )
        Group {
            if let gauge {
                ClaudeClosedGaugeView(gauge: gauge, height: height)
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
        .animation(.smooth(duration: 0.2), value: gauge == nil)
        .accessibilityElement()
        .accessibilityLabel(gauge?.accessibilityLabel ?? label(snapshot))
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

/// A ring filled to the percentage, with the number beside it: white, orange once it's worth
/// acting on, red when it's urgent.
private struct ClaudeClosedGaugeView: View {
    let gauge: ClaudeClosedGauge
    let height: CGFloat

    var body: some View {
        let color: Color = switch gauge.level {
        case .normal: Color.white.opacity(0.85)
        case .warning: .orange
        case .critical: .red
        }
        let metrics = ClaudeGaugeMetrics(height: height)
        HStack(spacing: ClaudeGaugeMetrics.spacing) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: gauge.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: metrics.ring, height: metrics.ring)
            Text("\(gauge.percent)%")
                .font(.system(size: metrics.fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
        // Against the outer edge; the wing's width keeps it clear of the camera housing.
        .padding(.trailing, ClaudeGaugeMetrics.outerPadding)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth(duration: 0.3), value: gauge.percent)
    }
}
