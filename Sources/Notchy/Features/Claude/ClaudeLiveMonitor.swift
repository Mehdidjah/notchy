import Combine
import Foundation

/// Which Claude sessions are open right now, as the closed notch needs to know.
struct ClaudeLiveSnapshot: Equatable, Sendable {
    /// Open sessions with Claude working on a reply.
    var working: [ClaudeLiveSession] = []
    /// Open sessions waiting for the user.
    var waiting: [ClaudeLiveSession] = []
    /// The island's own chat is getting a reply.
    var chatIsReplying = false

    var workingCount: Int { working.count + (chatIsReplying ? 1 : 0) }
    var isWorking: Bool { workingCount > 0 }
    var openCount: Int { working.count + waiting.count }
}

/// Keeps an eye on Claude Code's open sessions while the island is closed: re-reads the small
/// registry of open sessions every couple of seconds, with the end of each open session's
/// conversation when it changed (for how full its context is) and Claude Code's cached plan
/// usage when that changed. Says when Claude finishes so the notch can tell the user it's
/// their turn.
@MainActor
final class ClaudeLiveMonitor: ObservableObject {
    static let shared = ClaudeLiveMonitor()

    @Published private(set) var snapshot = ClaudeLiveSnapshot()

    /// Called when Claude stops working in a session: the session that finished, or nil when
    /// it was the island's own chat.
    var onFinished: ((ClaudeLiveSession?) -> Void)?

    /// A session must have been seen working at least this long before its end is announced,
    /// so a status that flickers doesn't announce anything.
    var minimumWorkToAnnounce: TimeInterval = 3

    private let loadSessions: @Sendable () async -> [ClaudeLiveSession]
    private let loadPlan: @Sendable () async -> ClaudePlanUsage?
    private let usage: ClaudeUsageStore
    private let now: () -> Date
    private var pollTask: Task<Void, Never>?
    private var chatObservation: AnyCancellable?
    /// When each session was first seen working in its current stretch of work.
    private var workStarted: [String: Date] = [:]
    private var chatReplyStarted: Date?

    init(
        loadSessions: (@Sendable () async -> [ClaudeLiveSession])? = nil,
        loadPlan: (@Sendable () async -> ClaudePlanUsage?)? = nil,
        usage: ClaudeUsageStore = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        let index = ClaudeSessionIndex.shared
        self.loadSessions = loadSessions ?? { await index.openSessions() }
        self.loadPlan = loadPlan ?? { await index.planUsage() }
        self.usage = usage
        self.now = now
    }

    var isRunning: Bool { pollTask != nil }

    func start(chat: ClaudeChatController = .shared, every interval: Duration = .seconds(2)) {
        guard pollTask == nil else { return }
        chatObservation = chat.$isReplying
            .removeDuplicates()
            .sink { [weak self] replying in self?.chatReplyingChanged(replying) }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        chatObservation = nil
        workStarted = [:]
        chatReplyStarted = nil
        snapshot = ClaudeLiveSnapshot()
    }

    /// Reads the open sessions once and announces the ones that just finished.
    func poll() async {
        let sessions = await loadSessions()
        let plan = await loadPlan()
        guard !Task.isCancelled else { return }
        usage.receive(plan)
        apply(sessions)
    }

    func apply(_ sessions: [ClaudeLiveSession]) {
        let time = now()
        let working = sessions.filter { $0.status == .busy }
        let waiting = sessions.filter { $0.status == .idle }
        let workingIDs = Set(working.map(\.sessionID))

        for session in waiting {
            guard let started = workStarted[session.sessionID] else { continue }
            if time.timeIntervalSince(started) >= minimumWorkToAnnounce {
                onFinished?(session)
            }
        }
        // Forget sessions that are no longer working (finished, or closed while working).
        workStarted = workStarted.filter { workingIDs.contains($0.key) }
        for session in working where workStarted[session.sessionID] == nil {
            workStarted[session.sessionID] = time
        }

        let next = ClaudeLiveSnapshot(working: working, waiting: waiting, chatIsReplying: snapshot.chatIsReplying)
        if next != snapshot { snapshot = next }
    }

    private func chatReplyingChanged(_ replying: Bool) {
        if replying {
            chatReplyStarted = now()
        } else if let started = chatReplyStarted {
            chatReplyStarted = nil
            if now().timeIntervalSince(started) >= minimumWorkToAnnounce { onFinished?(nil) }
        }
        guard snapshot.chatIsReplying != replying else { return }
        snapshot.chatIsReplying = replying
    }
}
