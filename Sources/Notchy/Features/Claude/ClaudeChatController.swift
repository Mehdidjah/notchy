import Foundation

/// Where chats run: an empty folder of Notchy's, so Claude Code finds no project there, and
/// so the Sessions list can leave these chats out.
enum ClaudeChatPaths {
    static var workingDirectory: URL {
        let base = (try? AppPaths.applicationSupportDirectory())
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(AppPaths.appFolderName)", isDirectory: true)
        return base.appendingPathComponent("Claude Chat", isDirectory: true)
    }

    static func prepareWorkingDirectory() throws -> URL {
        let directory = workingDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// A chat message on screen.
struct ClaudeChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable { case user, assistant }

    enum State: Equatable, Sendable {
        case complete
        /// The reply is still arriving.
        case streaming
        /// The user stopped the reply part way.
        case stopped
        case failed(String)
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State

    init(id: UUID = UUID(), role: Role, text: String, state: State = .complete) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
    }
}

/// The chat in the AI tools tab. Each message runs Claude Code once in print mode; the next one
/// resumes the same conversation, so Claude remembers the chat. The chat lives as long as the
/// app, so closing the island doesn't lose it, and a reply keeps arriving while it's closed.
@MainActor
final class ClaudeChatController: ObservableObject {
    static let shared = ClaudeChatController()

    @Published private(set) var messages: [ClaudeChatMessage] = []
    @Published var draft = ""
    @Published private(set) var isReplying = false
    /// False once a lookup found no Claude Code; nil until the first lookup.
    @Published private(set) var isClaudeCodeInstalled: Bool?

    private let settings: ClaudeSettings
    private let locator: ClaudeCodeLocator
    private let usage: ClaudeUsageStore
    private let contextWindows: ClaudeContextWindows
    private let runTurn: @Sendable (ClaudeChatRequest, URL, URL) -> AsyncStream<ClaudeStreamEvent>
    private var sessionID: String?
    private var replyTask: Task<Void, Never>?

    init(
        settings: ClaudeSettings = .shared,
        locator: ClaudeCodeLocator = .shared,
        usage: ClaudeUsageStore = .shared,
        contextWindows: ClaudeContextWindows = .shared,
        runTurn: @escaping @Sendable (ClaudeChatRequest, URL, URL) -> AsyncStream<ClaudeStreamEvent> = { request, executable, directory in
            ClaudeChatRunner.run(request, executable: executable, workingDirectory: directory)
        }
    ) {
        self.settings = settings
        self.locator = locator
        self.usage = usage
        self.contextWindows = contextWindows
        self.runTurn = runTurn
    }

    var hasConversation: Bool { !messages.isEmpty }

    var canSend: Bool {
        !isReplying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Looks for Claude Code so the tab can say when it's missing.
    func checkInstallation(refresh: Bool = false) async {
        isClaudeCodeInstalled = await locator.executable(refresh: refresh) != nil
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isReplying else { return }
        draft = ""
        messages.append(ClaudeChatMessage(role: .user, text: prompt))
        let reply = ClaudeChatMessage(role: .assistant, text: "", state: .streaming)
        messages.append(reply)
        isReplying = true
        let request = ClaudeChatRequest(prompt: prompt, model: settings.chatModel.alias, resumeSessionID: sessionID)
        replyTask = Task { [weak self] in
            await self?.runReply(request, replyID: reply.id)
        }
    }

    /// Stops the reply that is arriving; what came so far stays.
    func stop() {
        guard isReplying else { return }
        replyTask?.cancel()
        replyTask = nil
        updateReply(nil) { message in
            message.state = .stopped
        }
        isReplying = false
    }

    /// Clears the chat; the next message starts a new conversation.
    func newChat() {
        stop()
        messages = []
        sessionID = nil
    }

    // MARK: Private

    private func runReply(_ request: ClaudeChatRequest, replyID: UUID) async {
        let executable = await locator.executable()
        // Stopped or cleared while looking for Claude Code.
        guard !Task.isCancelled else { return }
        guard let executable else {
            isClaudeCodeInstalled = false
            finishReply(replyID, error: "Claude Code isn't installed. Install it, sign in once in Terminal with `claude`, then try again.")
            return
        }
        isClaudeCodeInstalled = true
        let directory: URL
        do {
            directory = try ClaudeChatPaths.prepareWorkingDirectory()
        } catch {
            finishReply(replyID, error: "Couldn't prepare the chat folder: \(error.localizedDescription)")
            return
        }

        var failure: String?
        var finished = false
        for await event in runTurn(request, executable, directory) {
            guard !Task.isCancelled else { break }
            switch event {
            case .started(let id, _):
                sessionID = id
            case .text(let text):
                updateReply(replyID) { $0.text += text }
            case .planUsage(let plan):
                // The freshest figures there are: straight from this reply.
                usage.receive(plan)
            case .contextWindows(let windows):
                contextWindows.learn(windows)
            case .finished(let id, let error):
                if let id { sessionID = id }
                failure = error
                finished = true
            }
        }
        guard !Task.isCancelled else { return }
        if !finished, failure == nil {
            failure = "Claude Code stopped before replying."
        }
        finishReply(replyID, error: failure)
    }

    private func finishReply(_ replyID: UUID, error: String?) {
        updateReply(replyID) { message in
            if let error {
                message.state = .failed(error)
            } else {
                message.state = .complete
            }
        }
        isReplying = false
        replyTask = nil
    }

    /// Changes the reply with `id`, or the last reply when `id` is nil.
    private func updateReply(_ id: UUID?, _ change: (inout ClaudeChatMessage) -> Void) {
        let index = id.map { id in messages.lastIndex { $0.id == id } }
            ?? messages.lastIndex { $0.role == .assistant }
        guard let index else { return }
        change(&messages[index])
    }
}
