import Darwin
import Foundation

/// A Claude Code process that is open right now, from `~/.claude/sessions/<pid>.json`.
struct ClaudeLiveSession: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Working on a reply.
        case busy
        /// Open and waiting for the user.
        case idle
    }

    let pid: Int32
    let sessionID: String
    let cwd: String?
    let status: Status
    let name: String?
    let updatedAt: Date?
    /// How full the session's context is, when its conversation file says.
    var context: ClaudeContextUsage? = nil

    /// Reads one registry file. Returns nil for anything that isn't a session record.
    static func parse(_ data: Data) -> ClaudeLiveSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0,
              let sessionID = object["sessionId"] as? String, !sessionID.isEmpty else { return nil }
        let updated = (object["updatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ClaudeLiveSession(
            pid: pid,
            sessionID: sessionID,
            cwd: object["cwd"] as? String,
            status: object["status"] as? String == "busy" ? .busy : .idle,
            name: object["name"] as? String,
            updatedAt: updated
        )
    }
}

/// One Claude Code conversation on this Mac, as the Sessions list shows it.
struct ClaudeSessionSummary: Identifiable, Equatable, Sendable {
    let id: String
    let fileURL: URL?
    let projectPath: String?
    let title: String?
    let lastPrompt: String?
    let lastReply: String?
    let gitBranch: String?
    let lastActive: Date
    var live: ClaudeLiveSession?
    var context: ClaudeContextUsage? = nil

    var isRunning: Bool { live != nil }

    /// The project folder's name, "~" for the home folder.
    var projectName: String {
        guard let projectPath, !projectPath.isEmpty else { return "Unknown project" }
        if projectPath == FileManager.default.homeDirectoryForCurrentUser.path { return "~" }
        return URL(fileURLWithPath: projectPath).lastPathComponent
    }

    /// The session's title, or what was last asked when it has none.
    var headline: String {
        title ?? lastPrompt ?? live?.name ?? "New session"
    }
}

/// One message of a session, for the read-only detail view.
struct ClaudeTranscriptEntry: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable { case user, assistant }

    let id: Int
    let role: Role
    let text: String
}

/// What a session file says about itself. Built from the end of the file, where the newest
/// title, prompt and reply are, so even very long sessions are read quickly.
struct ClaudeSessionFileSummary: Equatable, Sendable {
    var title: String?
    var lastPrompt: String?
    var lastReply: String?
    var cwd: String?
    var gitBranch: String?
    var lastTimestamp: Date?
    var transcript: [ClaudeTranscriptEntry] = []
    /// The context the session carries now, from its last reply or its last compaction.
    var contextTokens: Int?
    var model: String?
    /// The most context the session has been seen with, before any compaction.
    var largestContext = 0

    var isEmpty: Bool { title == nil && lastPrompt == nil && lastReply == nil }

    /// Reads JSON lines in file order; later lines win. `transcriptLimit` keeps that many of the
    /// last messages.
    static func read(lines: some Sequence<Substring>, transcriptLimit: Int = 0) -> ClaudeSessionFileSummary {
        var summary = ClaudeSessionFileSummary()
        var aiTitle: String?
        var customTitle: String?
        var transcript: [(ClaudeTranscriptEntry.Role, String)] = []

        for line in lines {
            guard line.first == "{",
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "ai-title":
                aiTitle = cleaned(object["aiTitle"] as? String) ?? aiTitle
            case "custom-title":
                customTitle = cleaned(object["customTitle"] as? String) ?? customTitle
            case "summary":
                aiTitle = aiTitle ?? cleaned(object["summary"] as? String)
            case "last-prompt":
                summary.lastPrompt = cleaned(object["lastPrompt"] as? String) ?? summary.lastPrompt
            case "system":
                guard let compacted = compactedContext(of: object) else { continue }
                summary.contextTokens = compacted.after
                summary.largestContext = max(summary.largestContext, compacted.before)
            case "user", "assistant":
                if let cwd = object["cwd"] as? String, !cwd.isEmpty { summary.cwd = cwd }
                if let branch = object["gitBranch"] as? String, !branch.isEmpty, branch != "HEAD" {
                    summary.gitBranch = branch
                }
                if let stamp = object["timestamp"] as? String, let date = parseTimestamp(stamp) {
                    summary.lastTimestamp = date
                }
                if type == "assistant", let reading = contextReading(of: object) {
                    summary.contextTokens = reading.tokens
                    summary.model = reading.model ?? summary.model
                    summary.largestContext = max(summary.largestContext, reading.tokens)
                }
                guard object["isSidechain"] as? Bool != true,
                      object["isMeta"] as? Bool != true,
                      object["isCompactSummary"] as? Bool != true,
                      object["isApiErrorMessage"] as? Bool != true,
                      let message = object["message"] as? [String: Any],
                      let text = visibleText(of: message) else { continue }
                if type == "assistant" {
                    summary.lastReply = text
                    transcript.append((.assistant, text))
                } else {
                    transcript.append((.user, text))
                }
            default:
                continue
            }
        }

        summary.title = customTitle ?? aiTitle
        if transcriptLimit > 0 {
            summary.transcript = transcript.suffix(transcriptLimit).enumerated().map { index, entry in
                ClaudeTranscriptEntry(id: index, role: entry.0, text: entry.1)
            }
        }
        return summary
    }

    /// The context the session carries now, from the newest reply or compaction in `lines`
    /// (in file order). Reads from the end and stops at the first one, so a poll stays cheap.
    static func latestContext(lines: [Substring]) -> (tokens: Int, model: String?)? {
        for line in lines.reversed() {
            guard line.first == "{",
                  line.contains("\"usage\"") || line.contains("compact_boundary"),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "assistant":
                if let reading = contextReading(of: object) { return reading }
            case "system":
                if let compacted = compactedContext(of: object) { return (compacted.after, nil) }
            default:
                continue
            }
        }
        return nil
    }

    /// Tokens a reply's request carried plus the reply itself, which the next request sends
    /// again: everything in the context at that point. Subagents' replies and Claude Code's
    /// own placeholder messages don't count.
    static func contextReading(of entry: [String: Any]) -> (tokens: Int, model: String?)? {
        guard entry["isSidechain"] as? Bool != true,
              let message = entry["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }
        let model = message["model"] as? String
        guard model != "<synthetic>" else { return nil }
        let keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
        let tokens = keys.reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
        return tokens > 0 ? (tokens, model) : nil
    }

    /// A compaction's sizes: the context before it, and what the summary left.
    static func compactedContext(of entry: [String: Any]) -> (before: Int, after: Int)? {
        guard entry["subtype"] as? String == "compact_boundary",
              let metadata = entry["compactMetadata"] as? [String: Any],
              let after = (metadata["postTokens"] as? NSNumber)?.intValue else { return nil }
        return ((metadata["preTokens"] as? NSNumber)?.intValue ?? 0, after)
    }

    /// The words a person would see in a message: its text blocks, without tool calls, tool
    /// results, or the tagged context Claude Code adds to prompts (`<system-reminder>` and such).
    static func visibleText(of message: [String: Any]) -> String? {
        let parts: [String]
        if let text = message["content"] as? String {
            parts = [text]
        } else if let blocks = message["content"] as? [[String: Any]] {
            parts = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
        } else {
            return nil
        }
        let visible = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<") }
        guard !visible.isEmpty else { return nil }
        return visible.joined(separator: "\n\n")
    }

    /// Single-line, trimmed, nil when empty.
    static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Reads Claude Code's own records of its sessions, read-only: conversations from
/// `~/.claude/projects/<project>/<session>.jsonl` and the processes open right now from
/// `~/.claude/sessions/<pid>.json`. Nothing here writes to those folders.
actor ClaudeSessionIndex {
    static let shared = ClaudeSessionIndex()

    /// Bytes read from the end of a session file; more only when that holds nothing useful.
    private static let tailBytes = 256 * 1024
    private static let largeTailBytes = 2 * 1024 * 1024
    private static let headBytes = 64 * 1024
    /// Enough for the last few replies, which is where an open session's context figure is.
    private static let contextTailBytes = 128 * 1024

    private let claudeDirectory: URL
    /// Claude Code's settings and caches, `~/.claude.json`; only its usage figures are read.
    private let configFile: URL
    private let contextWindows: ClaudeContextWindows
    private let excludedProjectPrefixes: @Sendable () -> [String]
    private let isProcessAlive: @Sendable (Int32) -> Bool
    private var cache: [URL: CachedFile] = [:]
    /// Open sessions' conversation files, and what each said last time it was read.
    private var openSessionFiles: [String: URL] = [:]
    private var openSessionContexts: [URL: CachedContext] = [:]
    private var planCache: CachedPlan?

    private struct CachedContext {
        let size: Int
        let modified: Date
        let reading: (tokens: Int, model: String?)?
    }

    private struct CachedPlan {
        let size: Int
        let modified: Date
        let usage: ClaudePlanUsage?
    }

    private struct CachedFile {
        let size: Int
        let modified: Date
        let summary: ClaudeSessionFileSummary
    }

    init(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true),
        configFile: URL? = nil,
        contextWindows: ClaudeContextWindows = .shared,
        excludedProjectPrefixes: @escaping @Sendable () -> [String] = { [ClaudeChatPaths.workingDirectory.path] },
        isProcessAlive: @escaping @Sendable (Int32) -> Bool = ClaudeSessionIndex.isClaudeProcessAlive
    ) {
        self.claudeDirectory = claudeDirectory
        self.configFile = configFile ?? claudeDirectory.deletingLastPathComponent().appendingPathComponent(".claude.json")
        self.contextWindows = contextWindows
        self.excludedProjectPrefixes = excludedProjectPrefixes
        self.isProcessAlive = isProcessAlive
    }

    /// The most recent sessions, open ones first, newest first within each group.
    func recentSessions(limit: Int = 24) -> [ClaudeSessionSummary] {
        let live = liveSessions()
        let liveByID = Dictionary(live.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        let files = sessionFiles()
        let excluded = excludedProjectPrefixes()

        // Every open session, plus the most recently written files.
        var chosen = Array(files.prefix(limit))
        for file in files.dropFirst(limit) where liveByID[file.id] != nil {
            chosen.append(file)
        }

        var seen = Set<String>()
        var sessions: [ClaudeSessionSummary] = []
        for file in chosen {
            let summary = fileSummary(file)
            let liveSession = liveByID[file.id]
            let projectPath = summary.cwd ?? liveSession?.cwd
            if let projectPath, excluded.contains(where: { projectPath.hasPrefix($0) }) { continue }
            guard !summary.isEmpty || liveSession != nil else { continue }
            seen.insert(file.id)
            sessions.append(ClaudeSessionSummary(
                id: file.id,
                fileURL: file.url,
                projectPath: projectPath,
                title: summary.title,
                lastPrompt: summary.lastPrompt,
                lastReply: summary.lastReply.flatMap(ClaudeSessionFileSummary.cleaned),
                gitBranch: summary.gitBranch,
                lastActive: max(file.modified, summary.lastTimestamp ?? .distantPast),
                live: liveSession,
                context: summary.contextTokens.map { tokens in
                    ClaudeContextUsage(
                        tokens: tokens,
                        window: contextWindows.window(for: summary.model, observedTokens: summary.largestContext),
                        model: summary.model
                    )
                }
            ))
        }
        // Drop entries for files that are gone.
        let chosenURLs = Set(chosen.map(\.url))
        cache = cache.filter { chosenURLs.contains($0.key) }

        // Open sessions that haven't written a file yet.
        for session in live where !seen.contains(session.sessionID) {
            if let cwd = session.cwd, excluded.contains(where: { cwd.hasPrefix($0) }) { continue }
            seen.insert(session.sessionID)
            sessions.append(ClaudeSessionSummary(
                id: session.sessionID,
                fileURL: nil,
                projectPath: session.cwd,
                title: nil,
                lastPrompt: nil,
                lastReply: nil,
                gitBranch: nil,
                lastActive: session.updatedAt ?? Date(),
                live: session
            ))
        }

        return sessions.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.lastActive > rhs.lastActive
        }
    }

    /// The Claude Code sessions open right now, without the island's own chats, each with how
    /// full its context is. Reads the small registry of open sessions and, for a session whose
    /// conversation changed, only the end of its file, so it is cheap enough to poll.
    func openSessions() -> [ClaudeLiveSession] {
        let excluded = excludedProjectPrefixes()
        let sessions = liveSessions().filter { session in
            guard let cwd = session.cwd else { return true }
            return !excluded.contains { cwd.hasPrefix($0) }
        }
        let open = Set(sessions.map(\.sessionID))
        openSessionFiles = openSessionFiles.filter { open.contains($0.key) }
        let files = Set(openSessionFiles.values)
        openSessionContexts = openSessionContexts.filter { files.contains($0.key) }
        return sessions.map { session in
            var session = session
            if let reading = latestContext(of: session) {
                session.context = ClaudeContextUsage(
                    tokens: reading.tokens,
                    window: contextWindows.window(for: reading.model, observedTokens: reading.tokens),
                    model: reading.model
                )
            }
            return session
        }
    }

    /// The plan's usage from Claude Code's own cache. Re-read only when the file changed.
    func planUsage() -> ClaudePlanUsage? {
        guard let (size, modified) = Self.stamp(of: configFile) else {
            planCache = nil
            return nil
        }
        if let planCache, planCache.size == size, planCache.modified == modified { return planCache.usage }
        // Claude Code may be writing it right now; keep the last figures and try again later.
        guard let data = try? Data(contentsOf: configFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return planCache?.usage
        }
        let usage = ClaudePlanUsage.parseClaudeCodeCache(object)
        planCache = CachedPlan(size: size, modified: modified, usage: usage)
        return usage
    }

    /// The last messages of a session, for its detail view.
    func transcript(of session: ClaudeSessionSummary, limit: Int = 12) -> [ClaudeTranscriptEntry] {
        guard let url = session.fileURL else { return [] }
        let tail = Self.readTail(of: url, bytes: Self.largeTailBytes)
        return ClaudeSessionFileSummary.read(lines: tail.lines, transcriptLimit: limit).transcript
    }

    // MARK: Files

    private func latestContext(of session: ClaudeLiveSession) -> (tokens: Int, model: String?)? {
        guard let url = conversationFile(of: session), let (size, modified) = Self.stamp(of: url) else { return nil }
        if let cached = openSessionContexts[url], cached.size == size, cached.modified == modified {
            return cached.reading
        }
        var tail = Self.readTail(of: url, bytes: Self.contextTailBytes)
        var reading = ClaudeSessionFileSummary.latestContext(lines: tail.lines)
        if reading == nil, !tail.isWholeFile {
            tail = Self.readTail(of: url, bytes: Self.largeTailBytes)
            reading = ClaudeSessionFileSummary.latestContext(lines: tail.lines)
        }
        openSessionContexts[url] = CachedContext(size: size, modified: modified, reading: reading)
        return reading
    }

    /// An open session's conversation file. Claude Code keeps it in a folder named after the
    /// working folder with every character but letters and digits turned into "-"; when that
    /// guess misses, the project folders are searched.
    private func conversationFile(of session: ClaudeLiveSession) -> URL? {
        let fileManager = FileManager.default
        if let known = openSessionFiles[session.sessionID], fileManager.fileExists(atPath: known.path) { return known }
        let projects = claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        let name = "\(session.sessionID).jsonl"
        var candidates: [URL] = []
        if let cwd = session.cwd {
            candidates.append(projects.appendingPathComponent(Self.projectFolderName(for: cwd), isDirectory: true))
        }
        candidates += (try? fileManager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for folder in candidates {
            let url = folder.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                openSessionFiles[session.sessionID] = url
                return url
            }
        }
        return nil
    }

    /// Size and modification date, straight from the file system. A kept `URL` can answer
    /// from its resource cache, which off the main run loop may never refresh.
    static func stamp(of url: URL) -> (size: Int, modified: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return ((attributes[.size] as? NSNumber)?.intValue ?? 0, attributes[.modificationDate] as? Date ?? .distantPast)
    }

    static func projectFolderName(for path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    private struct SessionFile {
        let id: String
        let url: URL
        let size: Int
        let modified: Date
    }

    /// Session files, newest first. Only the files directly inside each project folder; the
    /// subfolders hold subagent and tool output, not sessions.
    private func sessionFiles() -> [SessionFile] {
        let fileManager = FileManager.default
        let projects = claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let folders = try? fileManager.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var files: [SessionFile] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { continue }
            for entry in entries where entry.pathExtension == "jsonl" {
                guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                files.append(SessionFile(
                    id: entry.deletingPathExtension().lastPathComponent,
                    url: entry,
                    size: values.fileSize ?? 0,
                    modified: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        return files.sorted { $0.modified > $1.modified }
    }

    private func fileSummary(_ file: SessionFile) -> ClaudeSessionFileSummary {
        if let cached = cache[file.url], cached.size == file.size, cached.modified == file.modified {
            return cached.summary
        }
        var tail = Self.readTail(of: file.url, bytes: Self.tailBytes)
        var summary = ClaudeSessionFileSummary.read(lines: tail.lines)
        if summary.isEmpty || summary.contextTokens == nil, !tail.isWholeFile {
            // One huge line (a long tool result) can fill the whole tail.
            tail = Self.readTail(of: file.url, bytes: Self.largeTailBytes)
            summary = ClaudeSessionFileSummary.read(lines: tail.lines)
        }
        if (summary.title == nil || summary.cwd == nil), !tail.isWholeFile {
            // The first title and the working folder are written near the top.
            let head = ClaudeSessionFileSummary.read(lines: Self.readHead(of: file.url, bytes: Self.headBytes))
            summary.title = summary.title ?? head.title
            summary.cwd = summary.cwd ?? head.cwd
            summary.gitBranch = summary.gitBranch ?? head.gitBranch
        }
        cache[file.url] = CachedFile(size: file.size, modified: file.modified, summary: summary)
        return summary
    }

    struct Tail {
        let text: String
        let isWholeFile: Bool

        /// Complete lines only: when the read started mid-file, the first, partial line is dropped.
        var lines: [Substring] {
            let all = text.split(separator: "\n", omittingEmptySubsequences: true)
            return isWholeFile ? all : Array(all.dropFirst())
        }
    }

    static func readTail(of url: URL, bytes: Int) -> Tail {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Tail(text: "", isWholeFile: true) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return Tail(text: String(decoding: data, as: UTF8.self), isWholeFile: start == 0)
    }

    /// Complete lines from the start of the file.
    static func readHead(of url: URL, bytes: Int) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if data.count == bytes, !text.hasSuffix("\n"), !lines.isEmpty { lines.removeLast() }
        return lines
    }

    // MARK: Open sessions

    /// Open sessions from the registry. Only the `.json` records are read; the folder also
    /// holds per-process keys, which are none of Notchy's business.
    private func liveSessions() -> [ClaudeLiveSession] {
        let folder = claudeDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap(ClaudeLiveSession.parse) }
            .filter { isProcessAlive($0.pid) }
    }

    /// The registry can outlive a crashed process, and a process ID can be reused, so the
    /// process must exist and be Claude Code.
    @Sendable static func isClaudeProcessAlive(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        // Without a path (another user's process) trust the registry.
        guard length > 0 else { return true }
        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self).lowercased()
        return path.contains("claude")
    }
}
