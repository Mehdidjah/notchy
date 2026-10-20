import Foundation

/// How urgent a context or plan figure is.
enum ClaudeUsageLevel: Int, Comparable, Sendable {
    case normal
    /// Worth acting on soon: compact the session, or slow down.
    case warning
    /// About to happen: Claude Code compacts on its own, or the limit runs out.
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Context

/// How full a session's context is, measured against the point where Claude Code compacts it
/// on its own. Claude Code keeps room for the next reply and for the summary it writes when
/// compacting, so that point comes before the model's window is full: 967k on a 1M window.
struct ClaudeContextUsage: Equatable, Sendable {
    /// Tokens the last request sent plus the reply it got, which the next request carries.
    let tokens: Int
    /// The model's context window.
    let window: Int
    let model: String?

    static let replyReserve = 20_000
    static let summaryBuffer = 13_000
    /// Above this share of the auto-compact point Claude Code is about to compact.
    static let criticalFraction = 0.95

    var autoCompactAt: Int { max(1, window - Self.replyReserve - Self.summaryBuffer) }
    var tokensLeft: Int { max(0, autoCompactAt - tokens) }
    /// 0 when empty, 1 at the auto-compact point.
    var fraction: Double { min(max(Double(tokens) / Double(autoCompactAt), 0), 1) }
    var percent: Int { Int((fraction * 100).rounded()) }

    /// `warningFraction` is the user's threshold, as a share of the auto-compact point.
    func level(warningAt warningFraction: Double) -> ClaudeUsageLevel {
        if fraction >= Self.criticalFraction { return .critical }
        if fraction >= warningFraction { return .warning }
        return .normal
    }
}

/// Context windows by model. Claude Code reports a model's window with each reply it prints;
/// the chat learns them from there, and the rest is known from the model's name.
final class ClaudeContextWindows: @unchecked Sendable {
    static let shared = ClaudeContextWindows()

    static let standard = 200_000
    static let extended = 1_000_000

    private let defaults: UserDefaults
    private let key = "claude.contextWindows"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Remembers windows Claude Code reported, keyed by model ID.
    func learn(_ windows: [String: Int]) {
        let valid = Dictionary(
            windows.filter { $0.value > 0 }.map { (Self.baseID($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !valid.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let known = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        let merged = known.merging(valid) { _, new in new }
        guard merged != known else { return }
        defaults.set(merged, forKey: key)
    }

    /// The window for `model`. `observedTokens` is the largest context seen for the session:
    /// more than a standard window proves the extended one.
    func window(for model: String?, observedTokens: Int = 0) -> Int {
        if observedTokens > Self.standard { return Self.extended }
        guard let model else { return Self.extended }
        if model.contains("[1m]") { return Self.extended }
        let id = Self.baseID(model)
        lock.lock()
        let learned = (defaults.dictionary(forKey: key) as? [String: Int])?[id]
        lock.unlock()
        if let learned { return learned }
        return Self.generation(of: id).map { $0 >= 5 } == true ? Self.extended : Self.standard
    }

    /// "claude-opus-5-5[1m]" → "claude-opus-5-5".
    static func baseID(_ model: String) -> String {
        model.split(separator: "[").first.map(String.init) ?? model
    }

    /// The model generation: 5 for "claude-opus-5-5", 3 for "claude-3-5-sonnet-20241022".
    static func generation(of model: String) -> Int? {
        for part in model.split(separator: "-") {
            // A date suffix isn't a generation.
            if part.count <= 2, let number = Int(part) { return number }
        }
        return nil
    }
}

// MARK: - Plan limits

/// One of the Claude plan's usage limits: the five-hour session, the week, or the week for
/// one model.
struct ClaudePlanLimit: Equatable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        /// The rolling five-hour limit Claude calls a session.
        case session
        /// The weekly limit across all models.
        case weekly
        /// A weekly limit that applies to one model.
        case weeklyModel(String)
    }

    let kind: Kind
    /// 0...1 of the limit used.
    let fraction: Double
    let resetsAt: Date?
    /// How Claude itself rates it.
    let reportedLevel: ClaudeUsageLevel

    var id: Kind { kind }
    var percent: Int { Int((min(max(fraction, 0), 1) * 100).rounded()) }

    var title: String {
        switch kind {
        case .session: "Session"
        case .weekly: "Week"
        case .weeklyModel(let model): "\(model) week"
        }
    }

    /// The figure as of `now`: once the window has reset, nothing of it is used.
    func current(at now: Date) -> ClaudePlanLimit {
        guard let resetsAt, resetsAt <= now else { return self }
        return ClaudePlanLimit(kind: kind, fraction: 0, resetsAt: nil, reportedLevel: .normal)
    }

    func level(warningAt warningFraction: Double) -> ClaudeUsageLevel {
        let own: ClaudeUsageLevel = fraction >= 0.95 ? .critical : (fraction >= warningFraction ? .warning : .normal)
        return max(own, reportedLevel)
    }
}

/// The plan's usage, as Claude Code last heard it from Anthropic.
struct ClaudePlanUsage: Equatable, Sendable {
    var limits: [ClaudePlanLimit]
    var fetchedAt: Date

    var session: ClaudePlanLimit? { limits.first { $0.kind == .session } }
    var weekly: ClaudePlanLimit? { limits.first { $0.kind == .weekly } }

    func current(at now: Date) -> ClaudePlanUsage {
        ClaudePlanUsage(limits: limits.map { $0.current(at: now) }, fetchedAt: fetchedAt)
    }

    /// `newer`'s figures where it has them, this one's for the rest (a chat reply only reports
    /// the session and the week).
    func merged(with newer: ClaudePlanUsage) -> ClaudePlanUsage {
        guard newer.fetchedAt >= fetchedAt else { return newer.merged(with: self) }
        let replaced = Set(newer.limits.map(\.kind))
        return ClaudePlanUsage(limits: newer.limits + limits.filter { !replaced.contains($0.kind) }, fetchedAt: newer.fetchedAt)
    }

    /// Claude Code's own cache of the plan's usage: `cachedUsageUtilization` in `~/.claude.json`.
    /// Percentages there run 0...100.
    static func parseClaudeCodeCache(_ object: [String: Any]) -> ClaudePlanUsage? {
        guard let cache = object["cachedUsageUtilization"] as? [String: Any],
              let fetchedMs = (cache["fetchedAtMs"] as? NSNumber)?.doubleValue,
              let utilization = cache["utilization"] as? [String: Any] else { return nil }
        let fetchedAt = Date(timeIntervalSince1970: fetchedMs / 1000)
        var limits: [ClaudePlanLimit] = []

        if let entries = utilization["limits"] as? [[String: Any]] {
            for entry in entries {
                guard let percent = (entry["percent"] as? NSNumber)?.doubleValue else { continue }
                let kind: ClaudePlanLimit.Kind
                switch entry["kind"] as? String {
                case "session": kind = .session
                case "weekly_all": kind = .weekly
                case "weekly_scoped":
                    let scope = entry["scope"] as? [String: Any]
                    let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                    guard let model, !model.isEmpty else { continue }
                    kind = .weeklyModel(model)
                default: continue
                }
                guard !limits.contains(where: { $0.kind == kind }) else { continue }
                limits.append(ClaudePlanLimit(
                    kind: kind,
                    fraction: percent / 100,
                    resetsAt: (entry["resets_at"] as? String).flatMap(parseDate),
                    reportedLevel: level(severity: entry["severity"] as? String)
                ))
            }
        }
        // Older caches have only the two windows.
        for (key, kind) in [("five_hour", ClaudePlanLimit.Kind.session), ("seven_day", .weekly)] where !limits.contains(where: { $0.kind == kind }) {
            guard let window = utilization[key] as? [String: Any],
                  let percent = (window["utilization"] as? NSNumber)?.doubleValue else { continue }
            limits.append(ClaudePlanLimit(
                kind: kind,
                fraction: percent / 100,
                resetsAt: (window["resets_at"] as? String).flatMap(parseDate),
                reportedLevel: .normal
            ))
        }
        guard !limits.isEmpty else { return nil }
        return ClaudePlanUsage(limits: limits, fetchedAt: fetchedAt)
    }

    /// The `rate_limit_info` Claude Code prints while it replies. Utilization there runs 0...1.
    static func parseRateLimitEvent(_ info: [String: Any], receivedAt: Date) -> ClaudePlanUsage? {
        guard let windows = info["unifiedWindows"] as? [String: Any] else { return nil }
        let blocked = info["status"] as? String == "rejected"
        let reportedType = info["rateLimitType"] as? String
        var limits: [ClaudePlanLimit] = []
        for (key, kind) in [("five_hour", ClaudePlanLimit.Kind.session), ("seven_day", .weekly)] {
            guard let window = windows[key] as? [String: Any],
                  let fraction = (window["utilization"] as? NSNumber)?.doubleValue else { continue }
            let resets = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            limits.append(ClaudePlanLimit(
                kind: kind,
                fraction: fraction,
                resetsAt: resets,
                reportedLevel: blocked && reportedType == key ? .critical : .normal
            ))
        }
        guard !limits.isEmpty else { return nil }
        return ClaudePlanUsage(limits: limits, fetchedAt: receivedAt)
    }

    private static func level(severity: String?) -> ClaudeUsageLevel {
        switch severity {
        case "critical": .critical
        case "warning": .warning
        default: .normal
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Short figures for small spaces: "612k", "1.2M".
enum ClaudeTokenFormat {
    static func short(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000: return "\(tokens)"
        case ..<1_000_000: return "\(Int((Double(tokens) / 1_000).rounded()))k"
        default:
            let millions = Double(tokens) / 1_000_000
            return millions >= 10 ? "\(Int(millions.rounded()))M" : String(format: "%.1fM", millions)
        }
    }

    /// "resets 7:10 PM" today, "resets Thu" this week, otherwise "resets Oct 28".
    static func resets(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date, date > now else { return nil }
        if calendar.isDate(date, inSameDayAs: now) {
            return "resets \(date.formatted(date: .omitted, time: .shortened))"
        }
        if date.timeIntervalSince(now) < 6 * 86_400 {
            return "resets \(date.formatted(.dateTime.weekday(.abbreviated)))"
        }
        return "resets \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
