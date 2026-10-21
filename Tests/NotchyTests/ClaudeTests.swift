import Combine
import Foundation
import SwiftUI
import Testing
@testable import Notchy

struct ClaudeStreamParserTests {
    private func consume(_ lines: [String]) -> [ClaudeStreamEvent] {
        var parser = ClaudeStreamParser()
        return lines.flatMap { parser.consume($0) }
    }

    private func delta(_ text: String) -> String {
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}}"#
    }

    private let messageStart = #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#
    private let textBlockStart = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
    private let blockStop = #"{"type":"stream_event","event":{"type":"content_block_stop","index":0}}"#

    @Test func aReplyStreamsAsTextBetweenStartAndFinish() {
        let events = consume([
            #"{"type":"system","subtype":"init","session_id":"abc","model":"claude-haiku-5-5","tools":[]}"#,
            messageStart,
            textBlockStart,
            delta("Hel"),
            delta("lo"),
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#,
            blockStop,
            #"{"type":"result","subtype":"success","is_error":false,"result":"Hello","session_id":"abc"}"#,
        ])
        #expect(events == [
            .started(sessionID: "abc", model: "claude-haiku-5-5"),
            .text("Hel"),
            .text("lo"),
            .finished(sessionID: "abc", errorMessage: nil),
        ], "the complete message repeats the deltas and is not added again")
    }

    @Test func theCompleteMessageIsUsedWhenNoDeltasCame() {
        let events = consume([
            messageStart,
            #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"Hi"}]}}"#,
        ])
        #expect(events == [.text("Hi")])
    }

    @Test func aSecondTextBlockStartsANewParagraph() {
        let events = consume([messageStart, textBlockStart, delta("One."), blockStop, textBlockStart, delta("Two.")])
        #expect(events == [.text("One."), .text("\n\n"), .text("Two.")])
    }

    @Test func errorsCarryTheirReason() {
        let notSignedIn = consume([#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","session_id":"s"}"#])
        #expect(notSignedIn == [.finished(sessionID: "s", errorMessage: "Not logged in · Please run /login")])
        let failed = consume([#"{"type":"result","subtype":"error_during_execution","is_error":true}"#])
        #expect(failed == [.finished(sessionID: nil, errorMessage: "Claude Code ran into an error.")])
    }

    @Test func linesThatArentEventsAreSkipped() {
        #expect(consume(["", "not json", #"{"type":"rate_limit_event"}"#, #"{"no":"type"}"#]).isEmpty)
    }
}

struct ClaudeChatRequestTests {
    @Test func theChatRunsWithoutToolsAndKeepsThePromptOffTheCommandLine() {
        let request = ClaudeChatRequest(prompt: "--secret question", model: nil, resumeSessionID: nil)
        let arguments = request.arguments
        #expect(arguments.starts(with: ["-p", "--output-format", "stream-json"]))
        let tools = arguments.firstIndex(of: "--tools")
        #expect(tools.map { arguments[$0 + 1] } == "", "an empty tool list turns every tool off")
        #expect(arguments.contains("--safe-mode"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--disable-slash-commands"))
        #expect(!arguments.contains("--secret question"), "the message goes in on standard input")
        #expect(!arguments.contains("--model"))
        #expect(!arguments.contains("--resume"))
    }

    @Test func modelAndResumeAreAddedWhenSet() {
        let arguments = ClaudeChatRequest(prompt: "hi", model: "sonnet", resumeSessionID: "abc").arguments
        #expect(arguments.suffix(4) == ["--model", "sonnet", "--resume", "abc"])
    }

    @Test func theChildDoesNotInheritAParentSessionsMarkers() {
        let environment = ClaudeChatRunner.environment(
            base: ["CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "PATH": "/usr/bin", "HOME": "/Users/x"],
            home: "/Users/x"
        )
        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(environment["HOME"] == "/Users/x")
        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        #expect(paths.first == "/usr/bin")
        #expect(paths.contains("/Users/x/.local/bin"))
        #expect(paths.filter { $0 == "/usr/bin" }.count == 1)
    }

    @Test func aRunThatEndsWithoutAResultExplainsWhy() {
        #expect(ClaudeChatRunner.failureMessage(status: 1, stderr: "warming up\nError: not signed in\n\n") == "Claude Code stopped: Error: not signed in")
        #expect(ClaudeChatRunner.failureMessage(status: 9, stderr: "") == "Claude Code stopped unexpectedly (exit code 9).")
    }
}

struct ClaudeSessionFileTests {
    static func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func user(_ content: Any, cwd: String = "/Users/me/app", branch: String = "main", extra: [String: Any] = [:]) -> String {
        line(["type": "user", "cwd": cwd, "gitBranch": branch, "timestamp": "2026-10-20T10:00:00.000Z",
              "message": ["role": "user", "content": content]].merging(extra) { $1 })
    }

    static func assistant(_ text: String, extra: [String: Any] = [:]) -> String {
        line(["type": "assistant", "cwd": "/Users/me/app", "gitBranch": "main", "timestamp": "2026-10-20T10:01:00.000Z",
              "message": ["role": "assistant", "content": [["type": "thinking", "thinking": "hmm"], ["type": "text", "text": text]]]].merging(extra) { $1 })
    }

    @Test func theNewestTitlePromptAndReplyWin() {
        let lines = [
            Self.line(["type": "ai-title", "aiTitle": "Old title"]),
            Self.user("first question"),
            Self.assistant("first answer"),
            Self.line(["type": "ai-title", "aiTitle": "Fix the   login\nbug"]),
            Self.line(["type": "last-prompt", "lastPrompt": "why does it fail?"]),
            Self.assistant("Because the token expired."),
        ]
        let summary = ClaudeSessionFileSummary.read(lines: lines.map { Substring($0) })
        #expect(summary.title == "Fix the login bug", "whitespace is collapsed to one line")
        #expect(summary.lastPrompt == "why does it fail?")
        #expect(summary.lastReply == "Because the token expired.")
        #expect(summary.cwd == "/Users/me/app")
        #expect(summary.gitBranch == "main")
        #expect(summary.lastTimestamp != nil)
    }

    @Test func aTitleTheUserGaveBeatsTheGeneratedOne() {
        let lines = [
            Self.line(["type": "custom-title", "customTitle": "My name"]),
            Self.line(["type": "ai-title", "aiTitle": "Generated"]),
        ]
        #expect(ClaudeSessionFileSummary.read(lines: lines.map { Substring($0) }).title == "My name")
    }

    @Test func theTranscriptShowsOnlyWhatPeopleWouldSee() {
        let lines = [
            Self.user([["type": "text", "text": "<system-reminder>context</system-reminder>"], ["type": "text", "text": "Make it faster"]]),
            Self.user([["type": "tool_result", "tool_use_id": "1", "content": "output"]]),
            Self.user("meta note", extra: ["isMeta": true]),
            Self.assistant("side work", extra: ["isSidechain": true]),
            Self.assistant("Done, it's faster now."),
            Self.user("<command-name>/clear</command-name>"),
            "{ broken",
        ]
        let summary = ClaudeSessionFileSummary.read(lines: lines.map { Substring($0) }, transcriptLimit: 10)
        #expect(summary.transcript.map(\.role) == [.user, .assistant])
        #expect(summary.transcript.map(\.text) == ["Make it faster", "Done, it's faster now."])
    }

    @Test func theTranscriptKeepsTheLastMessages() {
        let lines = (1...5).map { Self.user("q\($0)") }
        let transcript = ClaudeSessionFileSummary.read(lines: lines.map { Substring($0) }, transcriptLimit: 2).transcript
        #expect(transcript.map(\.text) == ["q4", "q5"])
    }

    @Test func aDetachedHeadIsNotShownAsABranch() {
        let summary = ClaudeSessionFileSummary.read(lines: [Substring(Self.user("hi", branch: "HEAD"))])
        #expect(summary.gitBranch == nil)
    }

    @Test func liveRecordsAreParsed() {
        let record = #"{"pid":123,"sessionId":"s-1","cwd":"/Users/me/app","status":"busy","name":"app-1","updatedAt":1792507750806}"#
        let live = ClaudeLiveSession.parse(Data(record.utf8))
        #expect(live?.pid == 123)
        #expect(live?.status == .busy)
        #expect(live?.cwd == "/Users/me/app")
        #expect(live?.updatedAt == Date(timeIntervalSince1970: 1_792_507_750.806))
        #expect(ClaudeLiveSession.parse(Data(#"{"pid":0,"sessionId":"x"}"#.utf8)) == nil)
        #expect(ClaudeLiveSession.parse(Data("[]".utf8)) == nil)
    }

    @Test func resumeCommandsAreQuotedForTheShell() {
        #expect(ClaudeSessionCommands.resumeCommand(sessionID: "abc", projectPath: "/Users/me/my app")
            == "cd '/Users/me/my app' && claude --resume abc")
        #expect(ClaudeSessionCommands.resumeCommand(sessionID: "abc", projectPath: "/tmp/it's")
            == #"cd '/tmp/it'\''s' && claude --resume abc"#)
        #expect(ClaudeSessionCommands.resumeCommand(sessionID: "abc", projectPath: nil) == "claude --resume abc")
    }

    @Test func agesAreShort() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ClaudeSessionCommands.shortAge(from: now.addingTimeInterval(-20), now: now) == "now")
        #expect(ClaudeSessionCommands.shortAge(from: now.addingTimeInterval(-300), now: now) == "5m")
        #expect(ClaudeSessionCommands.shortAge(from: now.addingTimeInterval(-7_200), now: now) == "2h")
        #expect(ClaudeSessionCommands.shortAge(from: now.addingTimeInterval(-3 * 86_400), now: now) == "3d")
    }
}

struct ClaudeSessionIndexTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeSessionIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }

    private func writeSession(_ id: String, project: String, lines: [String], modified: Date) throws {
        let folder = root.appendingPathComponent("projects/\(project)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(id).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func writeLive(pid: Int32, sessionID: String, cwd: String, status: String, updatedAt: Date = Date()) throws {
        let millis = Int(updatedAt.timeIntervalSince1970 * 1000)
        let record = #"{"pid":\#(pid),"sessionId":"\#(sessionID)","cwd":"\#(cwd)","status":"\#(status)","updatedAt":\#(millis)}"#
        try record.write(to: root.appendingPathComponent("sessions/\(pid).json"), atomically: true, encoding: .utf8)
        // Keys beside the records must never be read.
        try "secret".write(to: root.appendingPathComponent("sessions/\(pid).abc.key"), atomically: true, encoding: .utf8)
    }

    @Test func openSessionsComeFirstThenTheNewest() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        try writeSession("old-open", project: "-a", lines: [
            ClaudeSessionFileTests.line(["type": "ai-title", "aiTitle": "Open one"]),
            ClaudeSessionFileTests.user("hi", cwd: "/Users/me/a"),
        ], modified: now.addingTimeInterval(-3_600))
        try writeSession("newest", project: "-b", lines: [
            ClaudeSessionFileTests.line(["type": "ai-title", "aiTitle": "Newest"]),
            ClaudeSessionFileTests.user("hello", cwd: "/Users/me/b"),
            ClaudeSessionFileTests.assistant("Hi there"),
        ], modified: now)
        try writeSession("chat", project: "-chat", lines: [
            ClaudeSessionFileTests.user("from the notch", cwd: "/Users/me/Library/Notchy/Claude Chat"),
        ], modified: now)
        try writeSession("empty", project: "-c", lines: [
            ClaudeSessionFileTests.line(["type": "queue-operation", "operation": "enqueue"]),
        ], modified: now)
        try writeLive(pid: 4242, sessionID: "old-open", cwd: "/Users/me/a", status: "busy")
        try writeLive(pid: 4343, sessionID: "dead", cwd: "/Users/me/d", status: "idle")
        try writeLive(pid: 4444, sessionID: "just-started", cwd: "/Users/me/e", status: "idle")

        let index = ClaudeSessionIndex(
            claudeDirectory: root,
            excludedProjectPrefixes: { ["/Users/me/Library/Notchy/Claude Chat"] },
            isProcessAlive: { $0 == 4242 || $0 == 4444 }
        )
        let sessions = await index.recentSessions()
        #expect(sessions.map(\.id) == ["just-started", "old-open", "newest"],
                "open sessions first; the chat folder, empty files and dead processes are left out")
        #expect(sessions[1].live?.status == .busy)
        #expect(sessions[1].title == "Open one")
        #expect(sessions[1].projectName == "a")
        #expect(sessions[2].lastReply == "Hi there")
        #expect(sessions[2].live == nil)
        #expect(sessions[0].fileURL == nil)

        let transcript = await index.transcript(of: sessions[2])
        #expect(transcript.map(\.text) == ["hello", "Hi there"])
    }

    @Test func aLongSessionIsSummarisedFromItsEnds() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = ClaudeSessionFileTests.user(String(repeating: "x", count: 4_000))
        var lines = [
            ClaudeSessionFileTests.line(["type": "ai-title", "aiTitle": "Early title"]),
            ClaudeSessionFileTests.user("start", cwd: "/Users/me/long"),
        ]
        lines += Array(repeating: filler, count: 200)
        lines.append(ClaudeSessionFileTests.line(["type": "last-prompt", "lastPrompt": "latest ask"]))
        try writeSession("long", project: "-long", lines: lines, modified: Date())

        let index = ClaudeSessionIndex(claudeDirectory: root, excludedProjectPrefixes: { [] }, isProcessAlive: { _ in false })
        let session = try #require(await index.recentSessions().first)
        #expect(session.title == "Early title", "the title near the top is found even though only the tail is parsed")
        #expect(session.lastPrompt == "latest ask")
    }
}

@MainActor
struct ClaudeChatControllerTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [ClaudeChatRequest] = []
        var requests: [ClaudeChatRequest] {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        func record(_ request: ClaudeChatRequest) {
            lock.lock()
            stored.append(request)
            lock.unlock()
        }
    }

    private func makeController(
        events: @escaping @Sendable (ClaudeChatRequest) -> [ClaudeStreamEvent],
        recorder: Recorder
    ) throws -> (ClaudeChatController, ClaudeSettings, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeChatTests-\(UUID().uuidString)", isDirectory: true)
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appendingPathComponent("claude")
        try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let suite = "ClaudeChatControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = ClaudeSettings(defaults: defaults)
        let controller = ClaudeChatController(
            settings: settings,
            locator: ClaudeCodeLocator(home: home),
            runTurn: { request, _, _ in
                recorder.record(request)
                return AsyncStream { continuation in
                    for event in events(request) { continuation.yield(event) }
                    continuation.finish()
                }
            }
        )
        return (controller, settings, home)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aReplyStreamsInAndTheNextMessageResumesTheConversation() async throws {
        let recorder = Recorder()
        let (chat, settings, home) = try makeController(events: { _ in
            [.started(sessionID: "conv-1", model: nil), .text("Hel"), .text("lo"), .finished(sessionID: "conv-1", errorMessage: nil)]
        }, recorder: recorder)
        defer { try? FileManager.default.removeItem(at: home) }

        chat.draft = "  Hi Claude  "
        #expect(chat.canSend)
        chat.send()
        #expect(chat.draft.isEmpty)
        #expect(chat.isReplying)
        #expect(!chat.canSend)
        #expect(await eventually { !chat.isReplying })
        #expect(chat.messages.map(\.text) == ["Hi Claude", "Hello"])
        #expect(chat.messages.last?.state == .complete)
        #expect(recorder.requests.first?.resumeSessionID == nil)
        #expect(recorder.requests.first?.model == nil)

        settings.chatModel = .haiku
        chat.draft = "And again"
        chat.send()
        #expect(await eventually { !chat.isReplying })
        #expect(recorder.requests.last?.resumeSessionID == "conv-1", "the second message continues the same conversation")
        #expect(recorder.requests.last?.model == "haiku")

        chat.newChat()
        #expect(chat.messages.isEmpty)
        chat.draft = "Fresh"
        chat.send()
        #expect(await eventually { !chat.isReplying })
        #expect(recorder.requests.last?.resumeSessionID == nil, "a new chat starts a new conversation")
    }

    @Test func aFailedReplyShowsWhy() async throws {
        let recorder = Recorder()
        let (chat, _, home) = try makeController(events: { _ in
            [.finished(sessionID: nil, errorMessage: "Not logged in")]
        }, recorder: recorder)
        defer { try? FileManager.default.removeItem(at: home) }

        chat.draft = "Hi"
        chat.send()
        #expect(await eventually { !chat.isReplying })
        #expect(chat.messages.last?.state == .failed("Not logged in"))
    }

    @Test func aRunThatEndsWithoutAResultIsAFailure() async throws {
        let recorder = Recorder()
        let (chat, _, home) = try makeController(events: { _ in [.text("partial")] }, recorder: recorder)
        defer { try? FileManager.default.removeItem(at: home) }

        chat.draft = "Hi"
        chat.send()
        #expect(await eventually { !chat.isReplying })
        #expect(chat.messages.last?.text == "partial")
        #expect(chat.messages.last?.state == .failed("Claude Code stopped before replying."))
    }

    @Test func emptyMessagesAreNotSent() throws {
        let recorder = Recorder()
        let (chat, _, home) = try makeController(events: { _ in [] }, recorder: recorder)
        defer { try? FileManager.default.removeItem(at: home) }
        chat.draft = "   \n "
        #expect(!chat.canSend)
        chat.send()
        #expect(chat.messages.isEmpty)
    }
}

@MainActor
struct ClaudeClosedNotchTests {
    private func session(_ id: String, _ status: ClaudeLiveSession.Status, cwd: String = "/Users/me/app") -> ClaudeLiveSession {
        ClaudeLiveSession(pid: 100, sessionID: id, cwd: cwd, status: status, name: nil, updatedAt: nil)
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    @Test func finishingAfterRealWorkIsAnnouncedOnce() {
        let clock = Clock()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, now: { clock.now })
        var finished: [String?] = []
        monitor.onFinished = { finished.append($0?.sessionID) }

        monitor.apply([session("a", .busy), session("b", .idle)])
        #expect(monitor.snapshot.workingCount == 1)
        #expect(monitor.snapshot.openCount == 2)
        clock.now += 10
        monitor.apply([session("a", .idle), session("b", .idle)])
        #expect(finished == ["a"])
        #expect(!monitor.snapshot.isWorking)
        clock.now += 10
        monitor.apply([session("a", .idle), session("b", .idle)])
        #expect(finished == ["a"], "a session that stays idle is not announced again")
    }

    @Test func aBlipOfWorkOrAClosedSessionIsNotAnnounced() {
        let clock = Clock()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, now: { clock.now })
        var finished: [String?] = []
        monitor.onFinished = { finished.append($0?.sessionID) }

        monitor.apply([session("a", .busy)])
        clock.now += 1
        monitor.apply([session("a", .idle)])
        #expect(finished.isEmpty, "a second of work isn't worth a note")

        monitor.apply([session("b", .busy)])
        clock.now += 30
        monitor.apply([])
        #expect(finished.isEmpty, "a session closed while working didn't finish")
        clock.now += 30
        monitor.apply([session("b", .idle)])
        #expect(finished.isEmpty)
    }

    @Test func visibilityFollowsTheSetting() {
        let working = ClaudeLiveSnapshot(working: [session("a", .busy)])
        let waiting = ClaudeLiveSnapshot(waiting: [session("a", .idle)])
        let chatting = ClaudeLiveSnapshot(chatIsReplying: true)
        let none = ClaudeLiveSnapshot()
        #expect(ClaudeClosedActivity.isVisible(snapshot: working, mode: .whileOpen))
        #expect(ClaudeClosedActivity.isVisible(snapshot: waiting, mode: .whileOpen))
        #expect(!ClaudeClosedActivity.isVisible(snapshot: none, mode: .whileOpen))
        #expect(ClaudeClosedActivity.isVisible(snapshot: working, mode: .whileWorking))
        #expect(ClaudeClosedActivity.isVisible(snapshot: chatting, mode: .whileWorking))
        #expect(!ClaudeClosedActivity.isVisible(snapshot: waiting, mode: .whileWorking))
        #expect(!ClaudeClosedActivity.isVisible(snapshot: working, mode: .never))
    }

    @Test func workingOutranksTheTimerAndWaitingYieldsToEverything() {
        let suite = "ClaudeClosedNotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = ClaudeLiveMonitor(loadSessions: { [] })
        let activity = ClaudeClosedActivity(monitor: monitor, settings: ClaudeSettings(defaults: defaults))
        #expect(!activity.isActivityVisible)

        monitor.apply([session("a", .idle)])
        #expect(activity.isActivityVisible)
        #expect(activity.priority > ClosedActivityPriority.privacy)
        #expect(activity.priority < ClosedActivityPriority.shelf)

        monitor.apply([session("a", .busy)])
        #expect(activity.priority > ClosedActivityPriority.music)
        #expect(activity.priority < ClosedActivityPriority.timer)

        var tapped = 0
        activity.onTap = { tapped += 1 }
        #expect(activity.handleTap() == false, "the click goes on to open the island")
        #expect(tapped == 1)
    }

    @Test func theChainIsToldOnlyWhenVisibilityOrPriorityChange() {
        let suite = "ClaudeClosedNotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = ClaudeLiveMonitor(loadSessions: { [] })
        let activity = ClaudeClosedActivity(monitor: monitor, settings: ClaudeSettings(defaults: defaults))
        var changes = 0
        let subscription = activity.activityDidChange.sink { changes += 1 }
        defer { subscription.cancel() }
        let initial = changes

        monitor.apply([session("a", .idle)])
        #expect(changes == initial + 1)
        monitor.apply([session("a", .idle), session("b", .idle)])
        #expect(changes == initial + 1, "another waiting session changes only the wing's number")
        monitor.apply([session("a", .busy), session("b", .idle)])
        #expect(changes == initial + 2)
    }

    @Test func theFinishedNoteNamesTheProject() {
        let peek = ClaudeFeature.finishedPeek(for: session("a", .idle, cwd: "/Users/me/dynamic-island"))
        #expect(peek.kind == .claude)
        #expect(peek.subtitle == "Claude finished")
        #expect(peek.title == "dynamic-island")
        let chat = ClaudeFeature.finishedPeek(for: nil)
        #expect(chat.subtitle == "Claude replied")
        #expect(chat.title.isEmpty)
    }

    @Test func theLogoFitsItsFrameWithOpenEyes() {
        let rect = CGRect(x: 0, y: 0, width: 48, height: 30)
        let path = ClaudeCodeLogoShape().path(in: rect)
        let bounds = path.boundingRect
        #expect(abs(bounds.width - 48) < 0.01)
        #expect(abs(bounds.height - 30) < 0.01)
        // Artwork (6.7, 9.5) is inside the left eye: x 6...7.488, y 8.102...10.949.
        let scale = 2.0
        let eye = CGPoint(x: 6.7 * scale, y: (9.5 - 5) * scale)
        #expect(!path.contains(eye, eoFill: true), "the eyes are holes")
        #expect(path.contains(CGPoint(x: 12 * scale, y: (12 - 5) * scale), eoFill: true))
        #expect(!path.contains(CGPoint(x: 1 * scale, y: (6 - 5) * scale), eoFill: true), "the space beside the head is empty")
    }
}
