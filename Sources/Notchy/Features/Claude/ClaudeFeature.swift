import Combine
import SwiftUI

/// Entry point the app coordinator calls: puts the Claude settings in the Settings window and
/// Claude on the closed notch (the open sessions, a note when Claude finishes, and a warning
/// when a session should be compacted or a plan limit is running out).
@MainActor
enum ClaudeFeature {
    private static var activity: ClaudeClosedActivity?
    private static var cancellables: Set<AnyCancellable> = []

    static func start(userSettings: UserSettings, model: NotchViewModel) {
        guard activity == nil else { return }
        let settings = ClaudeSettings.shared
        let monitor = ClaudeLiveMonitor.shared
        let attention = ClaudeAttention.shared

        let activity = ClaudeClosedActivity(monitor: monitor, settings: settings, attention: attention)
        activity.onTap = { [weak model] in
            guard let model else { return }
            if let sessionID = attention.top?.sessionID {
                // The session that needs compacting.
                showTab(in: model, section: .sessions)
                ClaudeSessionsModel.shared.focus(sessionID: sessionID)
            } else {
                showTab(in: model, section: monitor.snapshot.chatIsReplying && attention.top == nil ? .chat : .sessions)
            }
        }
        self.activity = activity
        model.activityCenter.register(activity)

        monitor.onFinished = { [weak model] session in
            guard settings.announcesFinish else { return }
            model?.activityCenter.requestSneakPeek(finishedPeek(for: session))
        }
        attention.onNewAlerts = { [weak model] alerts in
            guard settings.warnsAboutLimits, let alert = alerts.first else { return }
            model?.activityCenter.requestSneakPeek(ClaudeAlerts.peek(for: alert))
        }
        attention.start()

        // Watch the open sessions only while something uses them.
        settings.$closedNotch.combineLatest(settings.$announcesFinish, settings.$warnsAboutLimits)
            .map { mode, announces, warns in mode != .never || announces || warns }
            .removeDuplicates()
            .sink { needed in
                if needed { monitor.start() } else { monitor.stop() }
            }
            .store(in: &cancellables)

        SettingsSectionRegistry.shared.register(.claude, id: "claude") {
            ClaudeSettingsSection(userSettings: userSettings)
        }
    }

    static func stop(model: NotchViewModel) {
        cancellables.removeAll()
        ClaudeLiveMonitor.shared.stop()
        ClaudeLiveMonitor.shared.onFinished = nil
        ClaudeAttention.shared.stop()
        ClaudeAttention.shared.onNewAlerts = nil
        if let activity { model.activityCenter.unregister(id: activity.activityID) }
        activity = nil
        // A reply still arriving would otherwise outlive the app.
        ClaudeChatController.shared.stop()
    }

    /// The tab the island opens on while Claude is working on the closed notch. Asked on every
    /// hover too, so it only answers; it changes nothing.
    static func liveActivityTab(activeActivityID: String?) -> NotchTab? {
        guard activeActivityID == ClaudeClosedActivity.id, ClaudeLiveMonitor.shared.snapshot.isWorking else { return nil }
        return .claude
    }

    static func finishedPeek(for session: ClaudeLiveSession?) -> SneakPeek {
        let project = session?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        return SneakPeek(
            kind: .claude,
            systemImage: "checkmark.circle.fill",
            title: session == nil ? "" : (project ?? session?.name ?? ""),
            subtitle: session == nil ? "Claude replied" : "Claude finished",
            tint: ClaudeMark.orange,
            duration: .seconds(3)
        )
    }

    private static func showTab(in model: NotchViewModel, section: ClaudeTabSection) {
        guard model.availableTabs.contains(.claude) else { return }
        ClaudeSettings.shared.section = section
        model.selectTab(.claude)
    }
}

/// Settings ▸ Claude: the tab toggle, the chat's model, the closed notch, and where Claude
/// Code was found.
struct ClaudeSettingsSection: View {
    @ObservedObject var userSettings: UserSettings
    @ObservedObject private var settings = ClaudeSettings.shared
    @State private var installation: Installation = .checking

    private enum Installation: Equatable {
        case checking
        case found(path: String, version: String?)
        case missing
    }

    var body: some View {
        Section {
            Toggle("Show the AI tools tab", isOn: $userSettings.showClaudeTab)
        }
        Section("Chat") {
            Picker("Model", selection: $settings.chatModel) {
                ForEach(ClaudeChatModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            Text("The chat runs the Claude Code you're signed in to, so it uses your Claude plan. Claude gets no tools there: it can't read your files, run commands or browse. Chats are kept in Claude Code's history like any other session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Closed notch") {
            Picker("Show Claude", selection: $settings.closedNotch) {
                ForEach(ClaudeClosedNotchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Say when Claude finishes", isOn: $settings.announcesFinish)
            Text("Claude Code's mark hops while Claude works; a green dot means a session is waiting for you. Click it to see your sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Context and limits") {
            Toggle("Warn before a session needs compacting or a limit runs out", isOn: $settings.warnsAboutLimits)
            Picker("Suggest compacting at", selection: $settings.contextWarningPercent) {
                ForEach(ClaudeSettings.contextWarningChoices, id: \.self) { percent in
                    Text("\(percent)% full").tag(percent)
                }
            }
            Picker("Warn about plan limits at", selection: $settings.limitWarningPercent) {
                ForEach(ClaudeSettings.limitWarningChoices, id: \.self) { percent in
                    Text("\(percent)% used").tag(percent)
                }
            }
            Text("A session's context is measured against the point where Claude Code compacts it on its own, a little before the model's window is full. Plan limits are the five-hour session and the week, as Claude Code last heard them from Anthropic; a chat in the island brings them up to date.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Claude Code") {
            LabeledContent("Status") {
                switch installation {
                case .checking:
                    Text("Looking…").foregroundStyle(.secondary)
                case .found(_, let version):
                    Text(version.map { "Installed, version \($0)" } ?? "Installed")
                case .missing:
                    Text("Not found").foregroundStyle(.orange)
                }
            }
            if case .found(let path, _) = installation {
                LabeledContent("Location") {
                    Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            if installation == .missing {
                Text("Install Claude Code, then run `claude` once in Terminal to sign in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Again") { Task { await check(refresh: true) } }
            }
            Text("Sessions shows your recent Claude Code sessions from the files Claude Code keeps on this Mac. Notchy only reads them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await check(refresh: false) }
    }

    private func check(refresh: Bool) async {
        installation = .checking
        guard let executable = await ClaudeCodeLocator.shared.executable(refresh: refresh) else {
            installation = .missing
            return
        }
        let version = await ClaudeCodeLocator.shared.version()
        installation = .found(path: executable.path, version: version)
    }
}
