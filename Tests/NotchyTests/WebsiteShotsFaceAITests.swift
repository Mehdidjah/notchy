@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import os
import SwiftUI
import Testing
@testable import Notchy

/// The website's Face Check and AI tools tabs, built on made-up data in temporary folders.
///
/// Face Check runs on its own controller with an in-memory key and a camera that never opens a
/// device. AI tools reads a Claude Code folder written here, chats through a stand-in for the
/// `claude` tool in a chat folder of its own, and keeps every setting in its own defaults
/// suite; nothing reads or writes the user's camera, keychain, `~/.claude`, `~/.claude.json`
/// or Notchy's Application Support folder.
@MainActor
@Suite(.serialized)
struct WebsiteShotsFaceAITests {
    // MARK: Face Check

    /// One saved face that a check has just recognised, with Check now and Scan again ready.
    @Test func faceTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let folder = try WebsiteShots.temporaryDirectory("face")
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = FaceEnrollmentStore(fileURL: folder.appendingPathComponent("identities.sealed"), keyProvider: ShotFaceKey())
        try await store.upsert(FaceIdentity(name: "Me", samples: [FaceSample(
            descriptor: Array(repeating: 0, count: 128),
            modelIdentifier: FaceEmbedder.modelIdentifier,
            yaw: 0, pitch: 0, quality: 0.82,
            date: Date().addingTimeInterval(-3 * 86_400)
        )]))
        let controller = FaceCheckController(
            store: store,
            liveActivity: FaceCheckLiveActivity(haptics: ShotHaptics()),
            camera: ShotCamera()
        )
        controller.loadIdentities()
        #expect(await shotEventually { !controller.identities.isEmpty })

        let island = try WebsiteIsland()
        island.open(.face)
        #expect(island.model.selectedTab == .face)
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-face.png"),
            content: { tab in
                tab == .face ? AnyView(NotchFaceTabView(model: island.model, controller: controller)) : nil
            },
            beforeCapture: {
                // The tab turns the (stand-in) camera on as it appears. It goes off again so the
                // frame shows no camera picture, and the status and result are those of a
                // saved face that a check has just recognised.
                controller.stopCamera()
                controller.showcase(
                    status: "Face saved. You can use Check now.",
                    outcome: .init(matched: true, name: nil, distance: 0.31, limit: controller.preset.maximumDistance)
                )
            }
        )
        #expect(controller.cameraState == .off)
        #expect(controller.testOutcome?.matched == true)
    }

    // MARK: AI tools

    /// A short chat with Claude, the plan's usage in the header.
    @Test func aiChat() async throws {
        guard let output = WebsiteShots.output else { return }
        let workspace = try await ShotClaudeWorkspace()
        defer { workspace.remove() }
        workspace.settings.section = .chat
        workspace.settings.chatModel = .opus

        let chat = try workspace.makeChat()
        chat.draft = ShotConversation.prompt
        chat.send()
        #expect(await shotEventually { !chat.isReplying })
        #expect(chat.messages.count == 2)
        #expect(chat.messages.last?.state == .complete)
        // The reply ran in the temporary home's chat folder, not in Application Support.
        #expect(!workspace.chatDirectories.isEmpty)
        #expect(workspace.chatDirectories.allSatisfy { $0.standardizedFileURL.path.hasPrefix(workspace.root.standardizedFileURL.path) })

        let island = try WebsiteIsland()
        island.open(.claude)
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-ai.png"),
            content: workspace.content(for: island, chat: chat)
        )
    }

    /// The Claude Code sessions on this Mac: two open, one of them working, two closed.
    @Test func aiSessions() async throws {
        guard let output = WebsiteShots.output else { return }
        let workspace = try await ShotClaudeWorkspace()
        defer { workspace.remove() }
        workspace.settings.section = .sessions
        #expect(workspace.sessions.sessions.count == ShotSession.all.count)
        #expect(workspace.sessions.runningCount == 2)

        let island = try WebsiteIsland()
        island.open(.claude)
        // The working session's dot pulses (1 → 0.35 → 1 over 1.6 s from appearing); capture
        // lands at the end of a cycle (settle + 120 ms), where it is as bright as the open one.
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-ai-sessions.png"),
            content: workspace.content(for: island, chat: try workspace.makeChat()),
            settle: .milliseconds(1_480)
        )
    }
}

// MARK: - Claude Code on made-up projects

/// A temporary home with a Claude Code folder of sample sessions, the plan's usage, and the
/// settings and stores the AI tools tab is built from.
@MainActor
private final class ShotClaudeWorkspace {
    let root: URL
    let settings: ClaudeSettings
    let usage = ClaudeUsageStore()
    let contextWindows: ClaudeContextWindows
    let sessions: ClaudeSessionsModel
    /// The defaults suites the settings and context windows keep. Each is named by a path
    /// inside the temporary home, so its file is written there rather than to
    /// ~/Library/Preferences, and goes with the folder.
    private let suites: [String]
    /// The folders chat replies ran in, as the stand-in for the `claude` tool received them.
    private let chatDirectoryLog = OSAllocatedUnfairLock(initialState: [URL]())
    var chatDirectories: [URL] { chatDirectoryLog.withLock { $0 } }

    init() async throws {
        root = try WebsiteShots.temporaryDirectory("claude")
        let preferences = root.appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        suites = ["claude-settings", "claude-windows"].map { preferences.appendingPathComponent($0).path }
        let defaults = try suites.map { suite in
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }
        settings = ClaudeSettings(defaults: defaults[0])
        contextWindows = ClaudeContextWindows(defaults: defaults[1])

        let claude = root.appendingPathComponent(".claude", isDirectory: true)
        try ShotSession.writeAll(to: claude)
        let livePIDs = Set(ShotSession.all.compactMap(\.live?.pid))
        let index = ClaudeSessionIndex(
            claudeDirectory: claude,
            configFile: root.appendingPathComponent(".claude.json"),
            contextWindows: contextWindows,
            excludedProjectPrefixes: { [] },
            isProcessAlive: { livePIDs.contains($0) }
        )
        sessions = ClaudeSessionsModel(index: index, usage: usage)
        await sessions.refresh()
        usage.receive(Self.plan)
    }

    /// About a quarter of the five-hour session and two thirds of the week used.
    static var plan: ClaudePlanUsage {
        let now = Date()
        return ClaudePlanUsage(limits: [
            ClaudePlanLimit(kind: .session, fraction: 0.24, resetsAt: now.addingTimeInterval(3 * 3_600 - 600), reportedLevel: .normal),
            ClaudePlanLimit(kind: .weekly, fraction: 0.67, resetsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600), reportedLevel: .normal),
        ], fetchedAt: now)
    }

    /// A chat whose replies come from `ShotConversation` instead of Claude Code. The locator
    /// finds a stand-in `claude` in the temporary home, so no login shell is asked, and replies
    /// run in a chat folder inside that home rather than in Notchy's Application Support.
    func makeChat() throws -> ClaudeChatController {
        let bin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appendingPathComponent("claude")
        if !FileManager.default.fileExists(atPath: tool.path) {
            try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        let chatFolder = root.appendingPathComponent("Claude Chat", isDirectory: true)
        let log = chatDirectoryLog
        return ClaudeChatController(
            settings: settings,
            locator: ClaudeCodeLocator(home: root),
            usage: usage,
            contextWindows: contextWindows,
            runTurn: { request, _, directory in
                log.withLock { $0.append(directory) }
                return AsyncStream { continuation in
                    for event in ShotConversation.events(for: request) { continuation.yield(event) }
                    continuation.finish()
                }
            },
            workingDirectory: {
                try FileManager.default.createDirectory(at: chatFolder, withIntermediateDirectories: true)
                return chatFolder
            }
        )
    }

    func content(for island: WebsiteIsland, chat: ClaudeChatController) -> @MainActor @Sendable (NotchTab) -> AnyView? {
        let settings = settings, usage = usage, sessions = sessions
        return { tab in
            guard tab == .claude else { return nil }
            return AnyView(NotchClaudeTabView(model: island.model, chat: chat, sessions: sessions, settings: settings, usage: usage))
        }
    }

    /// Clears both defaults suites, then deletes the temporary home with their files in it.
    func remove() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        try? FileManager.default.removeItem(at: root)
    }
}

/// The chat's one exchange: a quick git question with a short, formatted answer.
private enum ShotConversation {
    static let prompt = "How do I undo my last commit but keep the changes?"

    static let reply = """
    Run `git reset --soft HEAD~1`: the commit is undone and its changes stay **staged**.
    Use `git reset HEAD~1` instead to keep them in your files, *unstaged*.
    """

    static func events(for request: ClaudeChatRequest) -> [ClaudeStreamEvent] {
        let session = request.resumeSessionID ?? "5b0c6f1e-8a47-4d0f-9a35-2f6e0c7d41a8"
        var events: [ClaudeStreamEvent] = [.started(sessionID: session, model: "claude-opus-5-5")]
        // Arrives in pieces, as a streamed reply does.
        var rest = Substring(reply)
        while !rest.isEmpty {
            let piece = rest.prefix(24)
            events.append(.text(String(piece)))
            rest = rest.dropFirst(piece.count)
        }
        events.append(.finished(sessionID: session, errorMessage: nil))
        return events
    }
}

/// One made-up Claude Code session: its conversation file and, when it is open, its entry in
/// the registry of running sessions.
private struct ShotSession {
    struct Live {
        let pid: Int32
        let busy: Bool
    }

    let id: String
    let project: String
    let branch: String
    let title: String
    let prompt: String
    let reply: String
    /// Tokens the last request read from the cache; the context is this plus a little more.
    let cachedTokens: Int
    let minutesAgo: Double
    var live: Live?

    var cwd: String { "/Users/sam/\(project)" }

    /// Open sessions first, then the newest; context gauges from nearly empty to nearly full.
    static let all: [ShotSession] = [
        ShotSession(
            id: "a3f1c2d4-6b7e-4f80-9c1a-2d3e4f5a6b70", project: "aurora-web", branch: "pricing-dark-mode",
            title: "Add dark mode to the pricing page",
            prompt: "Make the pricing page follow the dark theme",
            reply: "Moving PricingTable to theme colours.",
            cachedTokens: 389_400, minutesAgo: 0.2, live: Live(pid: 48_213, busy: true)
        ),
        ShotSession(
            id: "b7e2d9a0-1c3f-4a5b-8d6e-7f8091a2b3c4", project: "trail-notes", branch: "main",
            title: "Fix the crash when syncing offline edits",
            prompt: "The app crashes after syncing edits made offline",
            reply: "Fixed: the merge kept a stale index.",
            cachedTokens: 168_300, minutesAgo: 2, live: Live(pid: 48_391, busy: false)
        ),
        ShotSession(
            id: "c5d4e3f2-0a1b-4c2d-9e3f-4a5b6c7d8e9f", project: "lisbon-guide", branch: "docs",
            title: "Write the README for the city guide API",
            prompt: "Write a README for the API with setup and examples",
            reply: "README is ready, with curl examples.",
            cachedTokens: 822_400, minutesAgo: 24
        ),
        ShotSession(
            id: "d1e2f3a4-b5c6-4d7e-8f90-a1b2c3d4e5f6", project: "budget-cli", branch: "fast-import",
            title: "Speed up the CSV import",
            prompt: "Importing big CSV files is slow, can you speed it up?",
            reply: "A 40 MB file now imports in 1.4 s.",
            cachedTokens: 600_900, minutesAgo: 3 * 60 + 12
        ),
    ]

    static func writeAll(to claude: URL) throws {
        let fileManager = FileManager.default
        let sessionsFolder = claude.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)
        for session in all {
            let date = Date().addingTimeInterval(-session.minutesAgo * 60)
            let folder = claude
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(ClaudeSessionIndex.projectFolderName(for: session.cwd), isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(session.id).jsonl")
            try (session.lines(endingAt: date).joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: file.path)

            if let live = session.live {
                let record = ClaudeSessionFileTests.line([
                    "pid": Int(live.pid), "sessionId": session.id, "cwd": session.cwd,
                    "status": live.busy ? "busy" : "idle",
                    "updatedAt": Int(date.timeIntervalSince1970 * 1000),
                ])
                try record.write(to: sessionsFolder.appendingPathComponent("\(live.pid).json"), atomically: true, encoding: .utf8)
            }
        }
    }

    /// The title Claude gave it, then the last prompt and the reply with its token usage.
    func lines(endingAt date: Date) -> [String] {
        [
            ClaudeSessionFileTests.line(["type": "ai-title", "aiTitle": title, "sessionId": id]),
            entry("user", at: date.addingTimeInterval(-95), message: ["role": "user", "content": prompt]),
            entry("assistant", at: date, message: [
                "role": "assistant", "model": "claude-opus-5-5",
                "content": [["type": "text", "text": reply]],
                "usage": [
                    "input_tokens": 6, "cache_creation_input_tokens": 3_900,
                    "cache_read_input_tokens": cachedTokens, "output_tokens": 1_240,
                ],
            ]),
        ]
    }

    private func entry(_ type: String, at date: Date, message: [String: Any]) -> String {
        ClaudeSessionFileTests.line([
            "type": type, "sessionId": id, "cwd": cwd, "gitBranch": branch,
            "timestamp": Self.timestamp(date), "message": message,
        ])
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Face Check stand-ins

/// A sealing key kept in memory instead of the keychain.
private struct ShotFaceKey: FaceCheckKeyProvider {
    let key = SymmetricKey(size: .bits256)
    func existingKey() throws -> SymmetricKey? { key }
    func createKey() throws -> SymmetricKey { key }
    func deleteKey() throws {}
}

/// A camera that reports it started and never delivers a frame; its session has no inputs,
/// so no capture device is ever opened.
private final class ShotCamera: FaceCheckCameraCapturing, @unchecked Sendable {
    let session = AVCaptureSession()
    var authorizationStatus: AVAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func start(onFrame: @escaping FaceCheckCamera.FrameHandler, completion: @escaping @Sendable (Bool) -> Void) {
        completion(true)
    }
    func stop(completion: (@Sendable () -> Void)?) { completion?() }
}

private final class ShotHaptics: HapticFeedbackPerforming {
    func perform() {}
}

@MainActor
private func shotEventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
