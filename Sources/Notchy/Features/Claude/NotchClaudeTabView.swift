import AppKit
import SwiftUI

/// The AI tools tab: a chat with Claude through the Claude Code the user is signed in to, and
/// a read-only list of the Claude Code sessions on this Mac. "AI tools" and the Chat/Sessions
/// chips sit on top; the chat is a rounded prompt box with the model chip and a send button.
///
/// The prompt is an AppKit-backed text field, which doesn't follow a SwiftUI scale, so the tab
/// sizes itself with design sizes (`.island`) instead of `islandScaled()`.
struct NotchClaudeTabView: View {
    let model: NotchViewModel
    @ObservedObject private var chat: ClaudeChatController
    @ObservedObject private var sessions: ClaudeSessionsModel
    @ObservedObject private var settings: ClaudeSettings
    @ObservedObject private var usage: ClaudeUsageStore

    init(
        model: NotchViewModel,
        chat: ClaudeChatController = .shared,
        sessions: ClaudeSessionsModel = .shared,
        settings: ClaudeSettings = .shared,
        usage: ClaudeUsageStore = .shared
    ) {
        self.model = model
        _chat = ObservedObject(wrappedValue: chat)
        _sessions = ObservedObject(wrappedValue: sessions)
        _settings = ObservedObject(wrappedValue: settings)
        _usage = ObservedObject(wrappedValue: usage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7.island) {
            header
            Group {
                switch settings.section {
                case .chat:
                    ClaudeChatPane(chat: chat, settings: settings)
                case .sessions:
                    ClaudeSessionsPane(sessions: sessions, contextWarning: Double(settings.contextWarningPercent) / 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 14.island)
        .padding(.top, 3.island)
        .padding(.bottom, 8.island)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await sessions.keepRefreshing() }
        .task { await chat.checkInstallation() }
    }

    private var header: some View {
        HStack(spacing: 10.island) {
            Text("AI tools")
                .font(.system(size: 14.island, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 5.island) {
                ForEach(ClaudeTabSection.allCases) { section in
                    ClaudeFilterChip(
                        title: section.title,
                        count: section == .sessions ? sessions.runningCount : 0,
                        isSelected: settings.section == section
                    ) {
                        settings.section = section
                    }
                }
            }
            Spacer(minLength: 0)
            if let plan = usage.plan {
                ClaudePlanUsageStrip(plan: plan, warning: Double(settings.limitWarningPercent) / 100)
            }
            switch settings.section {
            case .chat:
                if chat.isReplying {
                    ClaudeHeaderButton(title: "Stop", systemImage: "xmark", help: "Stop the reply") { chat.stop() }
                }
                ClaudeHeaderButton(title: "New chat", systemImage: "square.and.pencil", help: "Start a new chat") {
                    chat.newChat()
                }
                .disabled(!chat.hasConversation)
            case .sessions:
                if sessions.selected != nil {
                    ClaudeHeaderButton(title: "All sessions", systemImage: "chevron.left", help: "Back to all sessions") {
                        sessions.closeDetail()
                    }
                }
            }
        }
        .frame(height: 20.island)
    }
}

// MARK: - Chat

private struct ClaudeChatPane: View {
    @ObservedObject var chat: ClaudeChatController
    @ObservedObject var settings: ClaudeSettings
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        if chat.isClaudeCodeInstalled == false, !chat.hasConversation {
            ClaudeMissingView { Task { await chat.checkInstallation(refresh: true) } }
        } else if chat.hasConversation {
            VStack(spacing: 6.island) {
                transcript
                compactComposer
            }
        } else {
            fullComposer
        }
    }

    /// The empty chat: a tall prompt box with the chips and the send button along its bottom.
    private var fullComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            promptField(placeholder: "Ask Claude anything…", lines: 1...3)
            Spacer(minLength: 4.island)
            HStack(spacing: 6.island) {
                ClaudeModelChip(settings: settings)
                ClaudeComposerChip(title: "New chat", systemImage: "plus") { chat.newChat() }
                    .disabled(!chat.hasConversation)
                Spacer(minLength: 0)
                sendButton
            }
        }
        .padding(.horizontal, 12.island)
        .padding(.top, 10.island)
        .padding(.bottom, 8.island)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(composerBackground(cornerRadius: 16.island))
        .contentShape(RoundedRectangle(cornerRadius: 16.island))
        .onTapGesture { isComposerFocused = true }
    }

    /// Under a conversation: one row with the model chip, the prompt and the send button.
    private var compactComposer: some View {
        HStack(alignment: .center, spacing: 8.island) {
            ClaudeModelChip(settings: settings)
            promptField(placeholder: "Reply to Claude…", lines: 1...2)
            sendButton
        }
        .padding(.leading, 6.island)
        .padding(.trailing, 5.island)
        .padding(.vertical, 5.island)
        .background(composerBackground(cornerRadius: 15.island))
        .contentShape(RoundedRectangle(cornerRadius: 15.island))
        .onTapGesture { isComposerFocused = true }
    }

    private func promptField(placeholder: String, lines: ClosedRange<Int>) -> some View {
        TextField(placeholder, text: $chat.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13.island))
            .foregroundStyle(.white)
            .lineLimit(lines)
            .focused($isComposerFocused)
            .onSubmit(send)
    }

    private var sendButton: some View {
        ClaudeSendButton(isReplying: chat.isReplying, isEnabled: chat.canSend) {
            if chat.isReplying { chat.stop() } else { send() }
        }
    }

    private func composerBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(isComposerFocused ? 0.22 : 0.1), lineWidth: 1)
            )
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7.island) {
                    ForEach(chat.messages) { message in
                        ClaudeMessageRow(role: message.role, text: message.text, state: message.state)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 2.island)
            }
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: chat.messages.count) {
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: chat.messages.last?.text.count) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "claude.chat.bottom"

    private func send() {
        chat.send()
        isComposerFocused = true
    }
}

/// One message: the user's on the right in a grey bubble, Claude's on the left after its mark.
private struct ClaudeMessageRow: View {
    let role: ClaudeChatMessage.Role
    let text: String
    let state: ClaudeChatMessage.State

    var body: some View {
        switch role {
        case .user:
            HStack {
                Spacer(minLength: 48.island)
                Text(text)
                    .font(.system(size: 12.island))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 9.island)
                    .padding(.vertical, 5.island)
                    .background(RoundedRectangle(cornerRadius: 10.island).fill(Color.white.opacity(0.12)))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 7.island) {
                ClaudeMark(size: 11.island)
                    .padding(.top, 2.island)
                VStack(alignment: .leading, spacing: 3.island) {
                    if text.isEmpty, state == .streaming {
                        ClaudeTypingDots()
                            .padding(.top, 4.island)
                    } else if !text.isEmpty {
                        Text(ClaudeMarkdown.attributed(text))
                            .font(.system(size: 12.island))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch state {
                    case .stopped:
                        Text("Stopped")
                            .font(.system(size: 10.island, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    case .failed(let reason):
                        Text(reason)
                            .font(.system(size: 11.island))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    case .complete, .streaming:
                        EmptyView()
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Shown in place of the chat when Claude Code isn't installed.
private struct ClaudeMissingView: View {
    let checkAgain: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10.island) {
            ClaudeMark(size: 18.island)
                .padding(.top, 2.island)
            VStack(alignment: .leading, spacing: 5.island) {
                Text("Claude Code isn't installed")
                    .font(.system(size: 13.island, weight: .semibold))
                    .foregroundStyle(.white)
                Text("The chat uses the Claude Code you're signed in to on this Mac. Install it, run `claude` once in Terminal to sign in, then check again.")
                    .font(.system(size: 11.island))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                ClaudeComposerChip(title: "Check again", systemImage: "arrow.clockwise", action: checkAgain)
            }
            Spacer(minLength: 0)
        }
        .padding(12.island)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16.island).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Sessions

private struct ClaudeSessionsPane: View {
    @ObservedObject var sessions: ClaudeSessionsModel
    let contextWarning: Double

    var body: some View {
        if let selected = sessions.selected {
            ClaudeSessionDetail(
                session: selected,
                transcript: sessions.transcript,
                isLoading: sessions.isLoadingTranscript,
                contextWarning: contextWarning
            )
        } else if !sessions.hasLoaded {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sessions.sessions.isEmpty {
            VStack(spacing: 4.island) {
                Text("No Claude Code sessions yet")
                    .font(.system(size: 13.island, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Sessions you start with Claude Code show up here.")
                    .font(.system(size: 11.island))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8.island), GridItem(.flexible(), spacing: 8.island)],
                    spacing: 8.island
                ) {
                    ForEach(sessions.sessions) { session in
                        ClaudeSessionCard(session: session, contextWarning: contextWarning) { sessions.open(session) }
                    }
                }
            }
        }
    }
}

/// A session in the list: status, title and time on top, then the project, the last reply and
/// how full the context is.
private struct ClaudeSessionCard: View {
    let session: ClaudeSessionSummary
    let contextWarning: Double
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3.island) {
                HStack(spacing: 6.island) {
                    ClaudeSessionStatusDot(live: session.live)
                    Text(session.headline)
                        .font(.system(size: 12.island, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4.island)
                    ClaudeRelativeTime(date: session.lastActive, live: session.live)
                }
                HStack(spacing: 5.island) {
                    Text(session.projectName)
                        .font(.system(size: 10.island, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let preview = session.lastReply ?? session.lastPrompt {
                        Text(preview)
                            .font(.system(size: 10.island))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    if let context = session.context {
                        Spacer(minLength: 4.island)
                        ClaudeContextGauge(context: context, warning: contextWarning)
                    }
                }
                .padding(.leading, 12.island)
            }
            .padding(.horizontal, 10.island)
            .padding(.vertical, 7.island)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11.island)
                    .fill(Color.white.opacity(isHovering ? 0.1 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 11.island))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .contextMenu { ClaudeSessionActions(session: session) }
        .help(helpText)
    }

    private var helpText: String {
        [session.projectPath, session.gitBranch.map { "Branch \($0)" }].compactMap(\.self).joined(separator: " · ")
    }
}

/// One session's last messages, read-only, with its project, status and context on top.
private struct ClaudeSessionDetail: View {
    let session: ClaudeSessionSummary
    let transcript: [ClaudeTranscriptEntry]
    let isLoading: Bool
    let contextWarning: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6.island) {
            HStack(alignment: .center, spacing: 6.island) {
                ClaudeSessionStatusDot(live: session.live)
                Text(session.headline)
                    .font(.system(size: 12.island, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.projectName)
                    .font(.system(size: 10.island, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer(minLength: 4.island)
                ClaudeRelativeTime(date: session.lastActive, live: session.live)
                Menu {
                    ClaudeSessionActions(session: session)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11.island, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 20.island, height: 16.island)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Session actions")
            }

            if let context = session.context {
                ClaudeContextBar(context: context, warning: contextWarning)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7.island) {
                        if transcript.isEmpty {
                            Text(isLoading ? "Loading…" : "No messages to show yet.")
                                .font(.system(size: 11.island))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        ForEach(transcript) { entry in
                            ClaudeMessageRow(
                                role: entry.role == .user ? .user : .assistant,
                                text: entry.text,
                                state: .complete
                            )
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 2.island)
                }
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .onChange(of: transcript) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private static let bottomID = "claude.session.bottom"
}

/// Copy the session's ID or the command that resumes it, or show its folder.
private struct ClaudeSessionActions: View {
    let session: ClaudeSessionSummary

    var body: some View {
        Button("Copy Resume Command", systemImage: "terminal") {
            copy(ClaudeSessionCommands.resumeCommand(sessionID: session.id, projectPath: session.projectPath))
        }
        Button("Copy Session ID", systemImage: "number") { copy(session.id) }
        if let path = session.projectPath {
            Button("Show Project in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum ClaudeSessionCommands {
    /// `cd '<project>' && claude --resume <id>`, quoted for the shell.
    static func resumeCommand(sessionID: String, projectPath: String?) -> String {
        let resume = "claude --resume \(sessionID)"
        guard let projectPath, !projectPath.isEmpty else { return resume }
        let quoted = "'" + projectPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "cd \(quoted) && \(resume)"
    }

    /// "now", "4m", "3h", "2d", then the date.
    static func shortAge(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

/// Green and pulsing while Claude is working, green while the session is open, grey once closed.
private struct ClaudeSessionStatusDot: View {
    let live: ClaudeLiveSession?
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6.island, height: 6.island)
            .opacity(live?.status == .busy && pulse ? 0.35 : 1)
            .animation(live?.status == .busy ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = true }
            .help(help)
            .accessibilityLabel(help)
    }

    private var color: Color {
        switch live?.status {
        case .busy, .idle: Color.green
        case nil: Color.white.opacity(0.25)
        }
    }

    private var help: String {
        switch live?.status {
        case .busy: "Claude is working"
        case .idle: "Open, waiting for you"
        case nil: "Closed"
        }
    }
}

/// "Working", "Open", or how long ago the session was last active.
private struct ClaudeRelativeTime: View {
    let date: Date
    let live: ClaudeLiveSession?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(label(now: context.date))
                .font(.system(size: 10.island, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(live == nil ? Color.white.opacity(0.4) : Color.green.opacity(0.85))
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func label(now: Date) -> String {
        switch live?.status {
        case .busy: "Working"
        case .idle: "Open"
        case nil: ClaudeSessionCommands.shortAge(from: date, now: now)
        }
    }
}

// MARK: - Context and limits

private extension ClaudeUsageLevel {
    func tint(normal: Color) -> Color {
        switch self {
        case .normal: normal
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// A small ring and the context's percentage, for a session card.
private struct ClaudeContextGauge: View {
    let context: ClaudeContextUsage
    let warning: Double

    var body: some View {
        let level = context.level(warningAt: warning)
        let color = level.tint(normal: Color.white.opacity(0.5))
        HStack(spacing: 3.island) {
            ClaudeRing(fraction: context.fraction, color: color, lineWidth: 1.6.island)
                .frame(width: 9.island, height: 9.island)
            Text("\(context.percent)%")
                .font(.system(size: 10.island, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .fixedSize()
        .help(ClaudeContextBar.description(of: context))
        .accessibilityElement()
        .accessibilityLabel("Context \(context.percent) percent full")
    }
}

/// The context of the open session: a bar to the auto-compact point, the token counts, and
/// what to do about it.
private struct ClaudeContextBar: View {
    let context: ClaudeContextUsage
    let warning: Double

    var body: some View {
        let level = context.level(warningAt: warning)
        let color = level.tint(normal: Color.white.opacity(0.6))
        HStack(spacing: 7.island) {
            Text("Context")
                .font(.system(size: 10.island, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            ClaudeBar(fraction: context.fraction, color: color)
                .frame(height: 4.island)
            Text("\(ClaudeTokenFormat.short(context.tokens)) of \(ClaudeTokenFormat.short(context.autoCompactAt))")
                .font(.system(size: 10.island, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize()
            Text(advice(level))
                .font(.system(size: 10.island, weight: .semibold))
                .foregroundStyle(color)
                .fixedSize()
        }
        .help(Self.description(of: context))
    }

    private func advice(_ level: ClaudeUsageLevel) -> String {
        switch level {
        case .normal: "\(context.percent)%"
        case .warning: "\(context.percent)% · /compact soon"
        case .critical: "\(context.percent)% · about to auto-compact"
        }
    }

    static func description(of context: ClaudeContextUsage) -> String {
        "Context: \(ClaudeTokenFormat.short(context.tokens)) tokens. Claude Code compacts on its own at \(ClaudeTokenFormat.short(context.autoCompactAt)) (\(ClaudeTokenFormat.short(context.window)) window), \(ClaudeTokenFormat.short(context.tokensLeft)) from now."
    }
}

/// The plan's five-hour session and weekly use, for the tab's header.
private struct ClaudePlanUsageStrip: View {
    let plan: ClaudePlanUsage
    let warning: Double

    var body: some View {
        // Once a limit's window resets its use drops to nothing; look again each minute.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let current = plan.current(at: context.date)
            HStack(spacing: 9.island) {
                ForEach([current.session, current.weekly].compactMap(\.self)) { limit in
                    item(limit)
                }
            }
            .help(Self.description(of: current, now: context.date))
        }
        .fixedSize()
    }

    private func item(_ limit: ClaudePlanLimit) -> some View {
        let color = limit.level(warningAt: warning).tint(normal: Color.white.opacity(0.6))
        return HStack(spacing: 4.island) {
            Text(limit.title)
                .font(.system(size: 10.island, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            ClaudeBar(fraction: limit.fraction, color: color)
                .frame(width: 26.island, height: 4.island)
            Text("\(limit.percent)%")
                .font(.system(size: 10.island, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .accessibilityElement()
        .accessibilityLabel("\(limit.title) limit \(limit.percent) percent used")
    }

    static func description(of plan: ClaudePlanUsage, now: Date) -> String {
        var lines = plan.limits.map { limit in
            ["\(limit.title): \(limit.percent)% used", ClaudeTokenFormat.resets(limit.resetsAt, now: now)]
                .compactMap(\.self).joined(separator: ", ")
        }
        lines.append("As of \(plan.fetchedAt.formatted(date: .omitted, time: .shortened))")
        return lines.joined(separator: "\n")
    }
}

private struct ClaudeBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.height, proxy.size.width * min(max(fraction, 0), 1)))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
    }
}

private struct ClaudeRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Pieces

/// Claude's mark: an asterisk in Claude's orange.
struct ClaudeMark: View {
    var size: CGFloat

    nonisolated static let orange = Color(red: 0.851, green: 0.467, blue: 0.341)

    var body: some View {
        Image(systemName: "asterisk")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Self.orange)
            .accessibilityHidden(true)
    }
}

/// "Chat" / "Sessions": a capsule, white when selected. `count` adds a small green badge.
private struct ClaudeFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.island) {
                Text(title)
                    .font(.system(size: 11.island, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.island, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4.island)
                        .frame(minWidth: 13.island, minHeight: 13.island)
                        .background(Capsule().fill(Color.green))
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.75))
            .padding(.horizontal, 10.island)
            .padding(.vertical, 3.island)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A plain text button for the header's right side ("New chat", "Stop").
private struct ClaudeHeaderButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.island) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.island, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.island, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isEnabled ? (isHovering ? 0.95 : 0.7) : 0.3))
            .padding(.horizontal, 8.island)
            .padding(.vertical, 3.island)
            .background(Capsule().fill(Color.white.opacity(isHovering && isEnabled ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A chip inside the prompt box.
private struct ClaudeComposerChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.island) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.island, weight: .bold))
                Text(title)
                    .font(.system(size: 11.island, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.35))
            .padding(.horizontal, 9.island)
            .padding(.vertical, 4.island)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The Claude chip: shows the model the chat uses and picks another.
private struct ClaudeModelChip: View {
    @ObservedObject var settings: ClaudeSettings

    var body: some View {
        Menu {
            Picker("Model", selection: $settings.chatModel) {
                ForEach(ClaudeChatModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4.island) {
                ClaudeMark(size: 9.island)
                Text(settings.chatModel == .automatic ? "Claude" : "Claude \(settings.chatModel.title)")
                    .font(.system(size: 11.island, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.island, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 9.island)
            .padding(.vertical, 4.island)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        // A plain button-style menu draws the label as it is: the borderless style would
        // drop its capsule and tint.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Model for the next message")
    }
}

/// The round send button: an up arrow, or a stop square while Claude replies.
private struct ClaudeSendButton: View {
    let isReplying: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        let active = isReplying || isEnabled
        Button(action: action) {
            Image(systemName: isReplying ? "stop.fill" : "arrow.up")
                .font(.system(size: (isReplying ? 9 : 11).island, weight: .bold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.35))
                .frame(width: 24.island, height: 24.island)
                .background(Circle().fill(active ? Color.white.opacity(0.92) : Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .help(isReplying ? "Stop the reply" : "Send")
        .accessibilityLabel(isReplying ? "Stop the reply" : "Send")
    }
}

/// Three dots that fade in turn while the first words of a reply are on their way.
private struct ClaudeTypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 3
            HStack(spacing: 3.island) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4.island, height: 4.island)
                        .opacity(0.25 + 0.6 * max(0, sin(phase - Double(index) * 0.7)))
                }
            }
        }
        .accessibilityLabel("Claude is replying")
    }
}

enum ClaudeMarkdown {
    /// Bold, italics, inline code and links; everything else stays as written.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
