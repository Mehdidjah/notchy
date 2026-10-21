import Combine
import Foundation
import Testing
@testable import Notchy

private func makeDefaults(_ name: String) -> UserDefaults {
    let suite = "\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// An assistant line carrying token usage, as Claude Code writes it.
private func reply(
    input: Int = 2, created: Int = 0, read: Int = 0, output: Int = 0,
    model: String = "claude-opus-5-5", sidechain: Bool = false
) -> String {
    ClaudeSessionFileTests.assistant("ok", extra: [
        "isSidechain": sidechain,
        "message": [
            "role": "assistant", "model": model,
            "content": [["type": "text", "text": "ok"]],
            "usage": ["input_tokens": input, "cache_creation_input_tokens": created,
                      "cache_read_input_tokens": read, "output_tokens": output],
        ],
    ])
}

private func compaction(before: Int, after: Int) -> String {
    ClaudeSessionFileTests.line([
        "type": "system", "subtype": "compact_boundary", "content": "Conversation compacted",
        "compactMetadata": ["trigger": "auto", "preTokens": before, "postTokens": after],
    ])
}

struct ClaudeContextTests {
    @Test func theAutoCompactPointLeavesRoomForAReplyAndASummary() {
        let context = ClaudeContextUsage(tokens: 483_500, window: 1_000_000, model: "claude-opus-5-5")
        #expect(context.autoCompactAt == 967_000, "the 968k compactions recorded on this Mac happened just past it")
        #expect(context.percent == 50)
        #expect(context.tokensLeft == 483_500)
        #expect(ClaudeContextUsage(tokens: 2_000_000, window: 1_000_000, model: nil).fraction == 1)
        #expect(ClaudeContextUsage(tokens: 0, window: 200_000, model: nil).autoCompactAt == 167_000)
    }

    @Test func levelsFollowTheThreshold() {
        func level(_ tokens: Int) -> ClaudeUsageLevel {
            ClaudeContextUsage(tokens: tokens, window: 1_000_000, model: nil).level(warningAt: 0.8)
        }
        #expect(level(700_000) == .normal)
        #expect(level(780_000) == .warning)
        #expect(level(920_000) == .critical, "95 % of the auto-compact point")
    }

    @Test func windowsComeFromWhatClaudeCodeReportedThenTheModelsName() {
        let windows = ClaudeContextWindows(defaults: makeDefaults("ClaudeContextTests"))
        #expect(windows.window(for: "claude-opus-5-5") == 1_000_000)
        #expect(windows.window(for: "claude-sonnet-4-6") == 200_000)
        #expect(windows.window(for: "claude-sonnet-4-6[1m]") == 1_000_000)
        #expect(windows.window(for: "claude-3-5-sonnet-20241022") == 200_000)
        #expect(windows.window(for: "claude-sonnet-4-6", observedTokens: 400_000) == 1_000_000, "more than 200k proves the larger window")

        windows.learn(["claude-sonnet-4-6[1m]": 1_000_000, "claude-opus-5-5": 500_000, "broken": 0])
        #expect(windows.window(for: "claude-sonnet-4-6") == 1_000_000)
        #expect(windows.window(for: "claude-opus-5-5") == 500_000)
        #expect(ClaudeContextWindows.generation(of: "claude-fable-5-1") == 5)
        #expect(ClaudeContextWindows.generation(of: "claude-opus-4-20250514") == 4)
    }

    @Test func aSessionsContextIsItsLastReplysTokens() {
        let summary = ClaudeSessionFileSummary.read(lines: [
            reply(input: 10, created: 1_000, read: 50_000, output: 500),
            reply(input: 2, created: 3_000, read: 300_000, output: 800),
            // Subagents and Claude Code's own placeholders don't count.
            reply(input: 1, created: 1, read: 900_000, output: 1, sidechain: true),
            reply(input: 0, created: 0, read: 0, output: 0, model: "<synthetic>"),
            ClaudeSessionFileTests.user("next"),
        ].map { Substring($0) })
        #expect(summary.contextTokens == 303_802)
        #expect(summary.model == "claude-opus-5-5")
        #expect(summary.largestContext == 303_802)
    }

    @Test func aCompactionLeavesOnlyTheSummary() {
        let lines = [
            reply(input: 2, read: 960_000, output: 1_000),
            compaction(before: 968_026, after: 29_642),
        ].map { Substring($0) }
        let summary = ClaudeSessionFileSummary.read(lines: lines)
        #expect(summary.contextTokens == 29_642)
        #expect(summary.largestContext == 968_026)
        #expect(ClaudeSessionFileSummary.latestContext(lines: lines)?.tokens == 29_642)

        let later = lines + [Substring(reply(input: 2, created: 40_000, read: 29_000, output: 100))]
        #expect(ClaudeSessionFileSummary.latestContext(lines: later)?.tokens == 69_102)
    }

    @Test func projectFoldersAreNamedAfterTheWorkingFolder() {
        #expect(ClaudeSessionIndex.projectFolderName(for: "/Users/a/dynamic iland/dynamic-island") == "-Users-a-dynamic-iland-dynamic-island")
        #expect(ClaudeSessionIndex.projectFolderName(for: "/Users/a/Café_1.0") == "-Users-a-Caf--1-0")
    }
}

struct ClaudePlanUsageTests {
    /// The shape of `cachedUsageUtilization` in `~/.claude.json`.
    static func cache(fetchedAtMs: Double = 1_792_509_583_313, sessionPercent: Double = 2, severity: String = "normal") -> [String: Any] {
        [
            "oauthAccount": ["emailAddress": "someone@example.com"],
            "cachedUsageUtilization": [
                "fetchedAtMs": fetchedAtMs,
                "utilization": [
                    "five_hour": ["utilization": 9, "resets_at": "2026-10-20T20:10:00.200191+00:00"],
                    "limits": [
                        ["kind": "session", "group": "session", "percent": sessionPercent, "severity": severity,
                         "resets_at": "2026-10-20T20:10:00.200191+00:00", "is_active": false],
                        ["kind": "weekly_all", "group": "weekly", "percent": 67, "severity": "normal",
                         "resets_at": "2026-10-22T08:00:00.200214+00:00", "is_active": false],
                        ["kind": "weekly_scoped", "group": "weekly", "percent": 100, "severity": "critical",
                         "resets_at": "2026-10-22T08:00:00.200409+00:00",
                         "scope": ["model": ["id": NSNull(), "display_name": "Fable"]], "is_active": true],
                    ],
                ],
            ],
        ]
    }

    @Test func claudeCodesCacheGivesEveryLimit() throws {
        let plan = try #require(ClaudePlanUsage.parseClaudeCodeCache(Self.cache()))
        #expect(plan.fetchedAt == Date(timeIntervalSince1970: 1_792_509_583.313))
        #expect(plan.session?.percent == 2, "the limits list wins over the older five_hour figure")
        #expect(plan.weekly?.percent == 67)
        let fable = try #require(plan.limits.first { $0.kind == .weeklyModel("Fable") })
        #expect(fable.reportedLevel == .critical)
        #expect(fable.title == "Fable week")
        #expect(abs((plan.session?.resetsAt?.timeIntervalSince1970 ?? 0) - 1_792_527_000.2) < 0.01, "2026-10-20 20:10 UTC")
    }

    @Test func anOlderCacheWithOnlyTheWindowsStillReads() throws {
        let object: [String: Any] = ["cachedUsageUtilization": [
            "fetchedAtMs": 1_000_000,
            "utilization": ["five_hour": ["utilization": 41, "resets_at": "2026-10-20T20:10:00+00:00"],
                            "seven_day": ["utilization": 12, "resets_at": "2026-10-22T08:00:00+00:00"]],
        ]]
        let plan = try #require(ClaudePlanUsage.parseClaudeCodeCache(object))
        #expect(plan.session?.percent == 41)
        #expect(plan.weekly?.percent == 12)
        #expect(ClaudePlanUsage.parseClaudeCodeCache(["projects": [:]]) == nil)
    }

    @Test func aRepliesRateLimitInfoUsesFractions() throws {
        let info: [String: Any] = [
            "status": "rejected", "rateLimitType": "five_hour", "resetsAt": 1_792_527_000,
            "unifiedWindows": ["five_hour": ["utilization": 1.0, "resetsAt": 1_792_527_000],
                               "seven_day": ["utilization": 0.67, "resetsAt": 1_792_656_000]],
        ]
        let now = Date(timeIntervalSince1970: 1_792_510_000)
        let plan = try #require(ClaudePlanUsage.parseRateLimitEvent(info, receivedAt: now))
        #expect(plan.fetchedAt == now)
        #expect(plan.session?.percent == 100)
        #expect(plan.session?.reportedLevel == .critical, "the reply was refused on this limit")
        #expect(plan.weekly?.percent == 67)
        #expect(plan.weekly?.reportedLevel == .normal)
    }

    @Test func newerFiguresWinAndTheRestAreKept() throws {
        let cached = try #require(ClaudePlanUsage.parseClaudeCodeCache(Self.cache()))
        let fresh = ClaudePlanUsage(
            limits: [ClaudePlanLimit(kind: .session, fraction: 0.4, resetsAt: nil, reportedLevel: .normal)],
            fetchedAt: cached.fetchedAt.addingTimeInterval(60)
        )
        let merged = cached.merged(with: fresh)
        #expect(merged.session?.percent == 40)
        #expect(merged.weekly?.percent == 67)
        #expect(merged.limits.contains { $0.kind == .weeklyModel("Fable") })
        #expect(merged.fetchedAt == fresh.fetchedAt)
        #expect(fresh.merged(with: cached) == merged, "order doesn't matter, the newer figure wins")
    }

    @Test func aWindowThatResetIsEmpty() throws {
        let plan = try #require(ClaudePlanUsage.parseClaudeCodeCache(Self.cache(sessionPercent: 90, severity: "warning")))
        let before = Date(timeIntervalSince1970: 1_792_520_000)
        let after = Date(timeIntervalSince1970: 1_792_530_000)
        #expect(plan.current(at: before).session?.percent == 90)
        #expect(plan.current(at: after).session?.percent == 0)
        #expect(plan.current(at: after).session?.reportedLevel == .normal)
        #expect(plan.current(at: after).weekly?.percent == 67)
    }

    @Test func levelsTakeClaudesOwnRatingIntoAccount() {
        let quiet = ClaudePlanLimit(kind: .session, fraction: 0.5, resetsAt: nil, reportedLevel: .normal)
        let rated = ClaudePlanLimit(kind: .session, fraction: 0.5, resetsAt: nil, reportedLevel: .warning)
        #expect(quiet.level(warningAt: 0.8) == .normal)
        #expect(rated.level(warningAt: 0.8) == .warning)
        #expect(ClaudePlanLimit(kind: .weekly, fraction: 0.85, resetsAt: nil, reportedLevel: .normal).level(warningAt: 0.8) == .warning)
        #expect(ClaudePlanLimit(kind: .weekly, fraction: 0.96, resetsAt: nil, reportedLevel: .normal).level(warningAt: 0.8) == .critical)
    }

    @Test func theParserPassesOnLimitsAndWindows() {
        var parser = ClaudeStreamParser()
        let limits = parser.consume(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.03,"resetsAt":1792527000}}},"session_id":"s"}"#)
        guard case .planUsage(let plan) = limits.first else {
            Issue.record("no plan usage: \(limits)")
            return
        }
        #expect(plan.session?.percent == 3)

        let result = parser.consume(#"{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s","modelUsage":{"claude-haiku-5-5":{"contextWindow":1000000},"claude-opus-5-5":{"contextWindow":1000000}}}"#)
        #expect(result.count == 2)
        #expect(result.first == .contextWindows(["claude-haiku-5-5": 1_000_000, "claude-opus-5-5": 1_000_000]))
        #expect(result.last == .finished(sessionID: "s", errorMessage: nil))
    }

    @Test func shortFigures() {
        #expect(ClaudeTokenFormat.short(950) == "950")
        #expect(ClaudeTokenFormat.short(612_400) == "612k")
        #expect(ClaudeTokenFormat.short(1_000_000) == "1.0M")
        let now = Date(timeIntervalSince1970: 1_792_510_000)
        #expect(ClaudeTokenFormat.resets(now.addingTimeInterval(-5), now: now) == nil)
        #expect(ClaudeTokenFormat.resets(now.addingTimeInterval(3 * 86_400), now: now)?.hasPrefix("resets ") == true)
    }
}

struct ClaudeUsageIndexTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)
    }

    private func index() -> ClaudeSessionIndex {
        ClaudeSessionIndex(
            claudeDirectory: root.appendingPathComponent(".claude", isDirectory: true),
            contextWindows: ClaudeContextWindows(defaults: makeDefaults("ClaudeUsageIndexTests")),
            excludedProjectPrefixes: { ["/Users/me/Library/Application Support/Notchy/Claude Chat"] },
            isProcessAlive: { _ in true }
        )
    }

    private func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func openSessionsCarryTheirContext() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write(#"{"pid":11,"sessionId":"aaa","cwd":"/Users/me/my app","status":"busy"}"#, to: ".claude/sessions/11.json")
        try write(#"{"pid":12,"sessionId":"bbb","cwd":"/Users/me/moved","status":"idle"}"#, to: ".claude/sessions/12.json")
        try write(#"{"pid":13,"sessionId":"ccc","cwd":"/Users/me/new","status":"idle"}"#, to: ".claude/sessions/13.json")
        // Named after the working folder…
        try write([reply(read: 100_000), reply(read: 500_000, output: 3_000)].joined(separator: "\n") + "\n",
                  to: ".claude/projects/-Users-me-my-app/aaa.jsonl")
        // …or found by searching when the folder was renamed since.
        try write(reply(read: 900_000, output: 1_000) + "\n", to: ".claude/projects/-Users-me-old-name/bbb.jsonl")

        let index = index()
        let sessions = await index.openSessions()
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionID, $0) })
        #expect(byID["aaa"]?.context?.tokens == 503_002)
        #expect(byID["aaa"]?.context?.window == 1_000_000)
        #expect(byID["bbb"]?.context?.tokens == 901_002)
        #expect(byID["ccc"] != nil)
        #expect(byID["ccc"]?.context == nil, "no conversation written yet")

        // The file grows: the next poll sees it.
        let aaa = root.appendingPathComponent(".claude/projects/-Users-me-my-app/aaa.jsonl")
        let handle = try FileHandle(forWritingTo: aaa)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((compaction(before: 503_002, after: 30_000) + "\n").utf8))
        try handle.close()
        let after = await index.openSessions()
        #expect(after.first { $0.sessionID == "aaa" }?.context?.tokens == 30_000)
    }

    @Test func theListShowsEachSessionsContext() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            ClaudeSessionFileTests.line(["type": "ai-title", "aiTitle": "Big one"]),
            ClaudeSessionFileTests.user("go"),
            reply(read: 870_000, output: 2_000),
        ].joined(separator: "\n") + "\n", to: ".claude/projects/-Users-me-app/s1.jsonl")
        let sessions = await index().recentSessions()
        let context = try #require(sessions.first?.context)
        #expect(context.tokens == 872_002)
        #expect(context.level(warningAt: 0.8) == .warning)
    }

    @Test func thePlanIsReadFromClaudeCodesCacheOnlyWhenItChanges() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let index = index()
        #expect(await index.planUsage() == nil, "no Claude Code config yet")

        let data = try JSONSerialization.data(withJSONObject: ClaudePlanUsageTests.cache(sessionPercent: 12))
        try data.write(to: root.appendingPathComponent(".claude.json"))
        #expect(await index.planUsage()?.session?.percent == 12)

        // Half-written: the last figures stay.
        try Data("{\"cachedUsage".utf8).write(to: root.appendingPathComponent(".claude.json"))
        #expect(await index.planUsage()?.session?.percent == 12)

        let newer = try JSONSerialization.data(withJSONObject: ClaudePlanUsageTests.cache(fetchedAtMs: 1_792_509_999_000, sessionPercent: 30))
        try newer.write(to: root.appendingPathComponent(".claude.json"))
        #expect(await index.planUsage()?.session?.percent == 30)
    }
}

@MainActor
struct ClaudeAlertTests {
    private func live(_ id: String, tokens: Int?, cwd: String = "/Users/me/app") -> ClaudeLiveSession {
        ClaudeLiveSession(
            pid: 1, sessionID: id, cwd: cwd, status: .idle, name: nil, updatedAt: nil,
            context: tokens.map { ClaudeContextUsage(tokens: $0, window: 1_000_000, model: nil) }
        )
    }

    private func plan(session: Double, weekly: Double = 0.1, model: Double = 1, resets: Date? = nil) -> ClaudePlanUsage {
        ClaudePlanUsage(limits: [
            ClaudePlanLimit(kind: .session, fraction: session, resetsAt: resets, reportedLevel: .normal),
            ClaudePlanLimit(kind: .weekly, fraction: weekly, resetsAt: nil, reportedLevel: .normal),
            ClaudePlanLimit(kind: .weeklyModel("Fable"), fraction: model, resetsAt: nil, reportedLevel: .critical),
        ], fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func alertsAreTheSessionsAndLimitsPastTheirWarningMostUrgentFirst() {
        let now = Date(timeIntervalSince1970: 100)
        let alerts = ClaudeAlerts.current(
            sessions: [live("calm", tokens: 100_000), live("full", tokens: 800_000, cwd: "/Users/me/site"), live("new", tokens: nil),
                       live("brim", tokens: 940_000)],
            plan: plan(session: 0.85),
            contextWarning: 0.8,
            limitWarning: 0.8,
            now: now
        )
        #expect(alerts.map(\.subject) == [.context(sessionID: "brim"), .limit(.session), .context(sessionID: "full")])
        #expect(alerts.first?.level == .critical)
        #expect(alerts.last?.project == "site")
        #expect(!alerts.contains { $0.subject == .limit(.weeklyModel("Fable")) }, "a per-model limit only shows in the tab")
    }

    @Test func notesSayWhatToDo() {
        let context = ClaudeAlert(subject: .context(sessionID: "x"), level: .warning, fraction: 0.82, project: "dynamic-island")
        let peek = ClaudeAlerts.peek(for: context)
        #expect(peek.kind == .claude)
        #expect(peek.subtitle == "Context 82% full")
        #expect(peek.title == "dynamic-island · /compact soon")

        let urgent = ClaudeAlert(subject: .context(sessionID: "x"), level: .critical, fraction: 0.97, project: "site")
        #expect(ClaudeAlerts.peek(for: urgent).subtitle == "About to auto-compact")
        #expect(ClaudeAlerts.peek(for: urgent).title == "site · 97% full")

        let now = Date(timeIntervalSince1970: 1_792_510_000)
        let limit = ClaudeAlert(subject: .limit(.session), level: .warning, fraction: 0.81, resetsAt: now.addingTimeInterval(3_600))
        #expect(ClaudeAlerts.peek(for: limit, now: now).subtitle == "Session limit 81% used")
        #expect(ClaudeAlerts.peek(for: limit, now: now).title.hasPrefix("resets "))
        let week = ClaudeAlert(subject: .limit(.weekly), level: .critical, fraction: 0.96)
        #expect(ClaudeAlerts.peek(for: week, now: now).subtitle == "Weekly limit almost used up")
        #expect(ClaudeAlerts.peek(for: week, now: now).title == "96%")
    }

    @Test func eachLevelIsAnnouncedOnce() {
        var announcer = ClaudeAlertAnnouncer()
        let subject = ClaudeAlert.Subject.context(sessionID: "x")
        func alert(_ level: ClaudeUsageLevel, _ fraction: Double) -> ClaudeAlert {
            ClaudeAlert(subject: subject, level: level, fraction: fraction)
        }
        #expect(announcer.update([alert(.warning, 0.81)]).count == 1)
        #expect(announcer.update([alert(.warning, 0.84)]).isEmpty)
        #expect(announcer.update([alert(.critical, 0.95)]).count == 1)
        #expect(announcer.update([alert(.warning, 0.94)]).isEmpty, "a wobble under the threshold isn't news")
        #expect(announcer.update([alert(.critical, 0.96)]).isEmpty)
        // Compacted: it can come up again later.
        #expect(announcer.update([]).isEmpty)
        #expect(announcer.update([alert(.warning, 0.8)]).count == 1)
    }

    @Test func attentionFollowsTheSessionsAndThePlan() async {
        let defaults = makeDefaults("ClaudeAlertTests")
        let settings = ClaudeSettings(defaults: defaults)
        let usage = ClaudeUsageStore()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, loadPlan: { nil }, usage: usage)
        let attention = ClaudeAttention(monitor: monitor, usage: usage, settings: settings, now: { Date(timeIntervalSince1970: 100) })
        var announced: [[ClaudeAlert.Subject]] = []
        attention.onNewAlerts = { announced.append($0.map(\.subject)) }

        monitor.apply([live("a", tokens: 500_000)])
        attention.recompute()
        #expect(attention.alerts.isEmpty)

        monitor.apply([live("a", tokens: 800_000)])
        attention.recompute()
        #expect(attention.top?.subject == .context(sessionID: "a"))
        usage.receive(plan(session: 0.9))
        attention.recompute()
        #expect(attention.alerts.count == 2)
        #expect(announced == [[.context(sessionID: "a")], [.limit(.session)]])

        settings.contextWarningPercent = 90
        attention.recompute()
        #expect(attention.alerts.map(\.subject) == [.limit(.session)], "the higher threshold clears the session")

        // Started, it looks again on its own.
        attention.start(recheckEvery: 3_600)
        defer { attention.stop() }
        monitor.apply([live("a", tokens: 950_000)])
        let deadline = ContinuousClock.now + .seconds(2)
        while attention.top?.subject != .context(sessionID: "a"), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(attention.top?.subject == .context(sessionID: "a"))
        #expect(attention.top?.level == .critical)
    }

    @Test func theNumberFitsInsideTheRingBesideTheNotch() {
        func width(_ metrics: ClaudeGaugeMetrics, _ number: String) -> CGFloat {
            TimerTextMeasurer.width(of: number, font: ClaudeGaugeMetrics.font(size: metrics.fontSize))
        }
        let clearance = ClaudeGaugeMetrics.notchGap + ClaudeGaugeMetrics.outerPadding
        let shrunk = ClaudeGaugeMetrics.minimumNumberScale
        for (height, hovering) in [(20.0, false), (32.0, true)] {
            let metrics = ClaudeGaugeMetrics(height: height)
            #expect(width(metrics, "99") <= metrics.innerWidth, "\(height) pt\(hovering ? ", hovered" : ""): two digits fit at full size")
            #expect(width(metrics, "100") * shrunk <= metrics.innerWidth, "\(height) pt: 100 fits once shrunk")
            #expect(metrics.wingWidth - metrics.ring >= clearance, "\(height) pt: the ring fits beside the notch")
            #expect(metrics.ring <= height, "the ring fits the wing's height")
        }
        // A menu-bar-height island on a display without a notch.
        let small = ClaudeGaugeMetrics(height: 12)
        #expect(width(small, "99") * shrunk <= small.innerWidth)
        #expect(ClaudeGaugeMetrics(height: 32).wingWidth > ClaudeGaugeMetrics(height: 20).wingWidth, "hovering makes room for a larger ring")
        #expect(ClaudeGaugeMetrics(height: 20).wingWidth <= 28, "the closed island stays narrow")
    }

    @Test func theRingFollowsTheSessionTheUserIsIn() {
        func session(_ id: String, _ status: ClaudeLiveSession.Status, tokens: Int?, at seconds: Double) -> ClaudeLiveSession {
            ClaudeLiveSession(
                pid: 1, sessionID: id, cwd: "/Users/me/\(id)", status: status, name: nil,
                updatedAt: Date(timeIntervalSince1970: seconds),
                context: tokens.map { ClaudeContextUsage(tokens: $0, window: 1_000_000, model: nil) }
            )
        }
        let older = session("older", .idle, tokens: 900_000, at: 10)
        let recent = session("recent", .idle, tokens: 330_000, at: 50)
        let busy = session("busy", .busy, tokens: 100_000, at: 5)

        let waiting = ClaudeLiveSnapshot(waiting: [older, recent])
        #expect(waiting.focus?.sessionID == "recent", "the one used last")
        #expect(ClaudeLiveSnapshot(working: [busy], waiting: [older, recent]).focus?.sessionID == "busy", "the one Claude works in")

        let gauge = ClaudeClosedActivity.gauge(snapshot: waiting, alerts: [], contextWarning: 0.8)
        #expect(gauge == .context(recent.context!, level: .normal, project: "recent"))
        #expect(gauge?.percent == 34)

        // Another session's alert doesn't take the ring; it comes as a note.
        let other = ClaudeAlert(subject: .context(sessionID: "older"), level: .warning, fraction: 0.93, project: "older")
        #expect(ClaudeClosedActivity.gauge(snapshot: waiting, alerts: [other], contextWarning: 0.8)?.percent == 34)
        // A limit about to stop every session does.
        let limit = ClaudeAlert(subject: .limit(.session), level: .critical, fraction: 0.97)
        #expect(ClaudeClosedActivity.gauge(snapshot: waiting, alerts: [limit, other], contextWarning: 0.8) == .limit(limit))
        let warning = ClaudeAlert(subject: .limit(.session), level: .warning, fraction: 0.85)
        #expect(ClaudeClosedActivity.gauge(snapshot: waiting, alerts: [warning], contextWarning: 0.8)?.percent == 34)

        // The session's own level colours it.
        let full = ClaudeLiveSnapshot(waiting: [session("full", .idle, tokens: 820_000, at: 60)])
        #expect(ClaudeClosedActivity.gauge(snapshot: full, alerts: [], contextWarning: 0.8)?.level == .warning)

        // A session that hasn't replied yet has nothing to show.
        let fresh = ClaudeLiveSnapshot(working: [session("new", .busy, tokens: nil, at: 70)], waiting: [recent])
        #expect(ClaudeClosedActivity.gauge(snapshot: fresh, alerts: [], contextWarning: 0.8) == nil)
    }

    @Test func theClosedNotchMakesRoomForTheRing() {
        let settings = ClaudeSettings(defaults: makeDefaults("ClaudeAlertTests"))
        let usage = ClaudeUsageStore()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, loadPlan: { nil }, usage: usage)
        let attention = ClaudeAttention(monitor: monitor, usage: usage, settings: settings)
        let activity = ClaudeClosedActivity(monitor: monitor, settings: settings, attention: attention)
        var changes = 0
        let subscription = activity.activityDidChange.sink { changes += 1 }
        defer { subscription.cancel() }
        let context = ClosedActivityContext(closedHeight: 32, notchWidth: 185, isHovering: false, gestureProgress: 0, hasHardwareNotch: true)

        monitor.apply([live("a", tokens: nil)])
        attention.recompute()
        #expect(activity.rightWingWidth(in: context) == context.wingBaseWidth, "the green dot until the session replies")
        let before = changes

        monitor.apply([live("a", tokens: 100_000)])
        attention.recompute()
        let metrics = ClaudeGaugeMetrics(height: context.contentHeight)
        #expect(activity.rightWingWidth(in: context) == metrics.wingWidth)
        #expect(activity.rightWingWidth(in: context) > context.wingBaseWidth)
        #expect(activity.leftWingWidth(in: context) == activity.rightWingWidth(in: context),
                "equal wings keep the black centre over the camera housing")
        #expect(changes > before, "the wider wing re-lays out the notch")
        let afterRing = changes

        monitor.apply([live("a", tokens: 200_000)])
        attention.recompute()
        #expect(changes == afterRing, "a new percentage doesn't re-lay out the notch")
    }

    @Test func aChatReplyBringsTheFiguresUpToDate() async throws {
        let usage = ClaudeUsageStore()
        let windows = ClaudeContextWindows(defaults: makeDefaults("ClaudeAlertTests"))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAlertTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bin.appendingPathComponent("claude"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("claude").path)
        let fresh = plan(session: 0.42)
        let controller = ClaudeChatController(
            settings: ClaudeSettings(defaults: makeDefaults("ClaudeAlertTests")),
            locator: ClaudeCodeLocator(home: home),
            usage: usage,
            contextWindows: windows,
            runTurn: { _, _, _ in
                AsyncStream { continuation in
                    continuation.yield(.started(sessionID: "s", model: "claude-sonnet-4-6"))
                    continuation.yield(.planUsage(fresh))
                    continuation.yield(.text("hi"))
                    continuation.yield(.contextWindows(["claude-sonnet-4-6": 1_000_000]))
                    continuation.yield(.finished(sessionID: "s", errorMessage: nil))
                    continuation.finish()
                }
            }
        )
        controller.draft = "hello"
        controller.send()
        let deadline = ContinuousClock.now + .seconds(2)
        while controller.isReplying, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(usage.plan?.session?.percent == 42)
        #expect(windows.window(for: "claude-sonnet-4-6") == 1_000_000)
    }
}
