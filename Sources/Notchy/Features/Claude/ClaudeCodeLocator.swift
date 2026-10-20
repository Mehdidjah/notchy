import Foundation

/// Finds the Claude Code command-line tool. Apps opened from the Finder don't get the shell's
/// PATH, so the usual install locations are checked first, then a login shell is asked once.
/// A miss is looked up again after a short while, so installing Claude Code is picked up
/// without relaunching Notchy.
actor ClaudeCodeLocator {
    static let shared = ClaudeCodeLocator()

    private let home: URL
    private let fileManager: FileManager
    private var found: URL?
    private var lastMiss: Date?
    private var cachedVersion: (path: String, version: String)?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    /// The `claude` executable, or nil when Claude Code isn't installed. `refresh` looks again
    /// straight away after a miss.
    func executable(refresh: Bool = false) async -> URL? {
        if let found, fileManager.isExecutableFile(atPath: found.path) { return found }
        found = nil
        if !refresh, let lastMiss, Date().timeIntervalSince(lastMiss) < 30 { return nil }

        if let path = Self.candidatePaths(home: home.path).first(where: fileManager.isExecutableFile(atPath:)) {
            found = URL(fileURLWithPath: path)
        } else if let path = await Self.lookUpInLoginShell(), fileManager.isExecutableFile(atPath: path) {
            found = URL(fileURLWithPath: path)
        }
        lastMiss = found == nil ? Date() : nil
        return found
    }

    /// "2.1.296" for the installed tool, read once per executable.
    func version() async -> String? {
        guard let executable = await executable() else { return nil }
        if let cachedVersion, cachedVersion.path == executable.path { return cachedVersion.version }
        guard let output = await Self.run(executable.path, ["--version"], timeout: 5) else { return nil }
        // "2.1.296 (Claude Code)"
        let version = output.split(separator: " ").first.map(String.init) ?? output
        guard !version.isEmpty else { return nil }
        cachedVersion = (executable.path, version)
        return version
    }

    /// Where the installers put the tool, most common first.
    nonisolated static func candidatePaths(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
    }

    /// Asks the user's login shell, which reads their profile, where `claude` is.
    private static func lookUpInLoginShell() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        guard let output = await run(shell, ["-l", "-c", "command -v claude"], timeout: 4) else { return nil }
        let path = output.split(separator: "\n").last.map(String.init) ?? ""
        return path.hasPrefix("/") ? path : nil
    }

    /// Runs a short command and returns its trimmed output, or nil when it fails or runs too long.
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = ClaudeChatRunner.environment()
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let once = ResumeOnce(continuation)
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard finished.terminationStatus == 0 else { return once.resume(nil) }
                once.resume(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            do {
                try process.run()
            } catch {
                once.resume(nil)
                return
            }
            let handle = ProcessHandle(process)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                handle.terminateIfRunning()
                once.resume(nil)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever of the exit or the timeout comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Lets a `Process` be stopped from another thread; `Process` itself is thread-safe for this.
final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }

    func waitUntilExit() {
        process.waitUntilExit()
    }

    func terminateIfRunning() {
        if process.isRunning { process.terminate() }
    }

    func interruptIfRunning() {
        if process.isRunning { process.interrupt() }
    }
}
