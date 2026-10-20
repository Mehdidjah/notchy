import Darwin
import Foundation

/// One turn of a chat: the message and how to run it.
struct ClaudeChatRequest: Equatable, Sendable {
    var prompt: String
    /// A model alias ("opus", "sonnet", "haiku"), or nil for Claude Code's own default.
    var model: String?
    /// The conversation to continue; nil starts a new one.
    var resumeSessionID: String?
    var systemPrompt: String = ClaudeChatRequest.chatSystemPrompt

    /// Claude Code in print mode, streaming JSON, as a plain chat: no tools, no MCP servers, no
    /// slash commands, and none of the user's hooks, plugins or CLAUDE.md files (`--safe-mode`).
    /// The message goes in on standard input, never on the command line.
    var arguments: [String] {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--safe-mode",
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--system-prompt", systemPrompt,
        ]
        if let model { arguments += ["--model", model] }
        if let resumeSessionID { arguments += ["--resume", resumeSessionID] }
        return arguments
    }

    static let chatSystemPrompt = """
        You are Claude, chatting with the user in a small panel at the top of their Mac's screen. \
        You have no tools here: you can't read or change their files, run commands or browse the \
        web, so say so if they ask for that. Keep replies short and to the point. Use plain \
        sentences, short lists and inline code; avoid headings, tables and long code blocks \
        unless they ask for them.
        """
}

/// Runs Claude Code for one chat turn and streams the reply. Cancelling the consuming task, or
/// dropping the stream, stops the process.
enum ClaudeChatRunner {
    /// Bytes of standard error kept for an error message.
    private static let stderrLimit = 8_192

    static func run(
        _ request: ClaudeChatRequest,
        executable: URL,
        workingDirectory: URL
    ) -> AsyncStream<ClaudeStreamEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = request.arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            let handle = ProcessHandle(process)
            let stopState = StopState()
            continuation.onTermination = { _ in
                guard handle.isRunning else { return }
                stopState.markStopped()
                // Interrupt first so Claude Code can save the turn, then make sure it ends.
                handle.interruptIfRunning()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { handle.terminateIfRunning() }
            }

            let errorTail = ErrorTail(limit: stderrLimit)
            let errorHandle = errors.fileHandleForReading
            errorHandle.readabilityHandler = { file in
                let data = file.availableData
                if data.isEmpty {
                    file.readabilityHandler = nil
                } else {
                    errorTail.append(data)
                }
            }

            do {
                try process.run()
            } catch {
                errorHandle.readabilityHandler = nil
                continuation.yield(.finished(sessionID: nil, errorMessage: "Couldn't start Claude Code: \(error.localizedDescription)"))
                continuation.finish()
                return
            }

            let prompt = Data(request.prompt.utf8)
            let reader = PipeReader(
                input: input.fileHandleForWriting,
                output: output.fileHandleForReading,
                prompt: prompt
            )
            DispatchQueue.global(qos: .userInitiated).async {
                var parser = ClaudeStreamParser()
                var sawFinish = false
                reader.readLines { line in
                    for event in parser.consume(line) {
                        if case .finished = event { sawFinish = true }
                        continuation.yield(event)
                    }
                }
                handle.waitUntilExit()
                errorHandle.readabilityHandler = nil
                if !sawFinish, !stopState.isStopped {
                    let message = failureMessage(status: handle.terminationStatus, stderr: errorTail.text)
                    continuation.yield(.finished(sessionID: nil, errorMessage: message))
                }
                continuation.finish()
            }
        }
    }

    /// The app's environment for the child, minus the markers a parent Claude Code session sets
    /// (Notchy may itself have been launched from one), plus the usual tool folders on PATH.
    static func environment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [String: String] {
        var environment = base
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT", "CLAUDE_AGENT_SDK_VERSION"] {
            environment[key] = nil
        }
        var paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] where !paths.contains(extra) {
            paths.append(extra)
        }
        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    /// A readable reason for a run that ended without a result.
    static func failureMessage(status: Int32, stderr: String) -> String {
        let detail = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        if let detail {
            return "Claude Code stopped: \(detail)"
        }
        return "Claude Code stopped unexpectedly (exit code \(status))."
    }
}

/// Writes the prompt to the child's standard input, then reads its output line by line.
/// Blocking reads, so it runs on a background queue.
private final class PipeReader: @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let prompt: Data

    init(input: FileHandle, output: FileHandle, prompt: Data) {
        self.input = input
        self.output = output
        self.prompt = prompt
    }

    func readLines(_ handleLine: (String) -> Void) {
        // A prompt larger than the pipe's buffer blocks until Claude Code reads it, which it
        // does first, so writing here before reading can't deadlock.
        try? input.write(contentsOf: prompt)
        try? input.close()

        // `read(2)` returns as soon as any output is there; `FileHandle.read(upToCount:)` would
        // wait for the whole count, holding the reply back until it ends.
        let descriptor = output.fileDescriptor
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        var buffer = Data()
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !lineData.isEmpty {
                    handleLine(String(decoding: lineData, as: UTF8.self))
                }
            }
        }
        if !buffer.isEmpty {
            handleLine(String(decoding: buffer, as: UTF8.self))
        }
    }
}

/// Remembers that the run was stopped on purpose, so its exit isn't reported as a failure.
private final class StopState: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func markStopped() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

/// The last few kilobytes of the child's standard error.
private final class ErrorTail: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if data.count > limit { data = data.suffix(limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
