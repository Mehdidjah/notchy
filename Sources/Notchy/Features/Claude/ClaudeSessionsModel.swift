import Foundation

/// The Sessions list's data: re-read every few seconds while the tab is on screen. Reads go
/// through `ClaudeSessionIndex` off the main thread and only touch changed files.
@MainActor
final class ClaudeSessionsModel: ObservableObject {
    static let shared = ClaudeSessionsModel()

    @Published private(set) var sessions: [ClaudeSessionSummary] = []
    @Published private(set) var hasLoaded = false
    /// The session open in the detail view, and its last messages.
    @Published private(set) var selected: ClaudeSessionSummary?
    @Published private(set) var transcript: [ClaudeTranscriptEntry] = []
    @Published private(set) var isLoadingTranscript = false

    private let index: ClaudeSessionIndex
    private let usage: ClaudeUsageStore
    private var transcriptTask: Task<Void, Never>?
    /// A session to open as soon as the list has it.
    private var pendingFocusID: String?

    init(index: ClaudeSessionIndex = .shared, usage: ClaudeUsageStore = .shared) {
        self.index = index
        self.usage = usage
    }

    var runningCount: Int { sessions.filter(\.isRunning).count }

    func refresh() async {
        let latest = await index.recentSessions()
        usage.receive(await index.planUsage())
        openPendingFocus(in: latest)
        guard latest != sessions || !hasLoaded else { return }
        sessions = latest
        hasLoaded = true
        if let selected, let updated = latest.first(where: { $0.id == selected.id }), updated != selected {
            self.selected = updated
            loadTranscript(for: updated)
        }
    }

    /// Refreshes now and then every `interval` until the calling task is cancelled (the tab's
    /// `.task`, which ends when the tab leaves the screen).
    func keepRefreshing(every interval: Duration = .seconds(4)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    /// Opens the session with `id`, now if the list has it or after the next refresh.
    func focus(sessionID id: String) {
        if let session = sessions.first(where: { $0.id == id }) {
            pendingFocusID = nil
            open(session)
        } else {
            pendingFocusID = id
        }
    }

    private func openPendingFocus(in list: [ClaudeSessionSummary]) {
        guard let id = pendingFocusID, let session = list.first(where: { $0.id == id }) else { return }
        pendingFocusID = nil
        open(session)
    }

    func open(_ session: ClaudeSessionSummary) {
        selected = session
        transcript = []
        loadTranscript(for: session)
    }

    func closeDetail() {
        transcriptTask?.cancel()
        selected = nil
        transcript = []
        isLoadingTranscript = false
    }

    private func loadTranscript(for session: ClaudeSessionSummary) {
        transcriptTask?.cancel()
        isLoadingTranscript = transcript.isEmpty
        transcriptTask = Task { [index] in
            let entries = await index.transcript(of: session)
            guard !Task.isCancelled, self.selected?.id == session.id else { return }
            self.transcript = entries
            self.isLoadingTranscript = false
        }
    }
}
