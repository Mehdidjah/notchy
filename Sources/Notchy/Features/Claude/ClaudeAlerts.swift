import Combine
import Foundation

/// The plan's usage as last heard: from Claude Code's own cache, or from the island chat's
/// replies, whichever is newer.
@MainActor
final class ClaudeUsageStore: ObservableObject {
    static let shared = ClaudeUsageStore()

    @Published private(set) var plan: ClaudePlanUsage?

    func receive(_ usage: ClaudePlanUsage?) {
        guard let usage else { return }
        let next = plan.map { $0.merged(with: usage) } ?? usage
        if next != plan { plan = next }
    }
}

/// Something worth telling the user: a session that should be compacted soon, or a plan limit
/// that is running out.
struct ClaudeAlert: Equatable, Sendable, Identifiable {
    enum Subject: Hashable, Sendable {
        case context(sessionID: String)
        case limit(ClaudePlanLimit.Kind)
    }

    let subject: Subject
    let level: ClaudeUsageLevel
    /// 0...1: of the auto-compact point for a session, of the limit for the plan.
    let fraction: Double
    /// The session's project folder name.
    var project: String? = nil
    var resetsAt: Date? = nil

    var id: Subject { subject }
    var percent: Int { Int((min(max(fraction, 0), 1) * 100).rounded()) }

    var sessionID: String? {
        if case .context(let id) = subject { return id }
        return nil
    }
}

enum ClaudeAlerts {
    /// Every session and limit at or past its warning, most urgent first. Only the five-hour
    /// session and the week across all models raise alerts; a per-model weekly limit only
    /// shows in the tab.
    static func current(
        sessions: [ClaudeLiveSession],
        plan: ClaudePlanUsage?,
        contextWarning: Double,
        limitWarning: Double,
        now: Date
    ) -> [ClaudeAlert] {
        var alerts: [ClaudeAlert] = []
        for session in sessions {
            guard let context = session.context else { continue }
            let level = context.level(warningAt: contextWarning)
            guard level > .normal else { continue }
            alerts.append(ClaudeAlert(
                subject: .context(sessionID: session.sessionID),
                level: level,
                fraction: context.fraction,
                project: session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ))
        }
        for limit in plan?.current(at: now).limits ?? [] where limit.kind == .session || limit.kind == .weekly {
            let level = limit.level(warningAt: limitWarning)
            guard level > .normal else { continue }
            alerts.append(ClaudeAlert(subject: .limit(limit.kind), level: level, fraction: limit.fraction, resetsAt: limit.resetsAt))
        }
        return alerts.sorted { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            return lhs.fraction > rhs.fraction
        }
    }

    /// The note under the closed notch for an alert that just came up.
    static func peek(for alert: ClaudeAlert, now: Date = Date()) -> SneakPeek {
        let subtitle: String
        let title: String
        switch alert.subject {
        case .context:
            let project = alert.project ?? "Claude Code"
            if alert.level == .critical {
                subtitle = "About to auto-compact"
                title = "\(project) · \(alert.percent)% full"
            } else {
                subtitle = "Context \(alert.percent)% full"
                title = "\(project) · /compact soon"
            }
        case .limit(let kind):
            let name = kind == .session ? "Session limit" : "Weekly limit"
            let resets = ClaudeTokenFormat.resets(alert.resetsAt, now: now)
            if alert.level == .critical {
                subtitle = "\(name) almost used up"
                title = ["\(alert.percent)%", resets].compactMap(\.self).joined(separator: " · ")
            } else {
                subtitle = "\(name) \(alert.percent)% used"
                title = resets ?? ""
            }
        }
        return SneakPeek(
            kind: .claude,
            systemImage: "exclamationmark.triangle.fill",
            title: title,
            subtitle: subtitle,
            tint: alert.level == .critical ? .red : .orange,
            duration: .seconds(5)
        )
    }
}

/// Decides which alerts are news. Each session or limit is announced when it reaches warning
/// and again when it reaches critical; once it falls back to normal (compacted, or the window
/// reset) it can be announced again.
struct ClaudeAlertAnnouncer {
    private var announced: [ClaudeAlert.Subject: ClaudeUsageLevel] = [:]

    mutating func update(_ alerts: [ClaudeAlert]) -> [ClaudeAlert] {
        var fresh: [ClaudeAlert] = []
        var next: [ClaudeAlert.Subject: ClaudeUsageLevel] = [:]
        for alert in alerts where alert.level > .normal {
            let previous = announced[alert.subject] ?? .normal
            if alert.level > previous { fresh.append(alert) }
            // A figure that wobbles around a threshold doesn't announce twice.
            next[alert.subject] = max(previous, alert.level)
        }
        announced = next
        return fresh
    }
}

/// The alerts right now, for the closed notch and the notes under it. Follows the open
/// sessions, the plan's usage and the thresholds in Settings, and looks again each minute so a
/// limit whose window has reset clears.
@MainActor
final class ClaudeAttention: ObservableObject {
    static let shared = ClaudeAttention()

    @Published private(set) var alerts: [ClaudeAlert] = []
    var top: ClaudeAlert? { alerts.first }
    /// Called with alerts that just came up.
    var onNewAlerts: (([ClaudeAlert]) -> Void)?

    private let monitor: ClaudeLiveMonitor
    private let usage: ClaudeUsageStore
    private let settings: ClaudeSettings
    private let now: () -> Date
    private var announcer = ClaudeAlertAnnouncer()
    private var cancellables: Set<AnyCancellable> = []

    init(
        monitor: ClaudeLiveMonitor = .shared,
        usage: ClaudeUsageStore = .shared,
        settings: ClaudeSettings = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.monitor = monitor
        self.usage = usage
        self.settings = settings
        self.now = now
    }

    func start(recheckEvery interval: TimeInterval = 60) {
        guard cancellables.isEmpty else { return }
        let thresholds = settings.$contextWarningPercent.combineLatest(settings.$limitWarningPercent).map { _ in () }
        Publishers.Merge4(
            monitor.$snapshot.map { _ in () },
            usage.$plan.map { _ in () },
            thresholds,
            Timer.publish(every: interval, on: .main, in: .common).autoconnect().map { _ in () }
        )
        // Published values change just before they're stored; look once they have.
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.recompute() }
        .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        announcer = ClaudeAlertAnnouncer()
        if !alerts.isEmpty { alerts = [] }
    }

    func recompute() {
        let next = ClaudeAlerts.current(
            sessions: monitor.snapshot.working + monitor.snapshot.waiting,
            plan: usage.plan,
            contextWarning: Double(settings.contextWarningPercent) / 100,
            limitWarning: Double(settings.limitWarningPercent) / 100,
            now: now()
        )
        if next != alerts { alerts = next }
        let fresh = announcer.update(next)
        if !fresh.isEmpty { onNewAlerts?(fresh) }
    }
}
