import Foundation
import Testing
@testable import Notchy

/// The website's Clipboard tab: a believable history copied over the last hour.
@MainActor
@Suite(.serialized)
struct WebsiteShotsClipboardTests {
    @Test func clipboardTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland(items: Self.sampleClips)
        island.open(.clipboard)
        try await island.renderOpen(to: output.appendingPathComponent("tab-clipboard.png"))
    }

    static var sampleClips: [Clip] {
        func clip(_ value: String, app: String, kind: ClipboardItemKind, style: ClipboardCardStyle, minutesAgo: Double, pinned: Bool = false, urlTitle: String? = nil) -> Clip {
            var clip = Clip(title: value, value: value, detail: app, kind: kind, style: style, symbolName: "", isPinned: pinned)
            let date = Date().addingTimeInterval(-minutesAgo * 60)
            clip.createdAt = date
            clip.updatedAt = date
            clip.lastCopiedAt = date
            clip.urlTitle = urlTitle
            return clip
        }
        return [
            clip("Lunch moved to 1:30, same place.", app: "Messages", kind: .text, style: .light, minutesAgo: 2, pinned: true),
            clip("https://developer.apple.com/design/human-interface-guidelines", app: "Safari", kind: .link, style: .teal, minutesAgo: 6, urlTitle: "Human Interface Guidelines"),
            clip("#E46642", app: "Figma", kind: .color, style: .blue, minutesAgo: 9),
            clip("let island = Notch(open: .home)", app: "Xcode", kind: .code, style: .dark, minutesAgo: 14),
            clip("18 Rua Augusta, Lisbon", app: "Maps", kind: .text, style: .dark, minutesAgo: 27),
            clip("Ship the update before Friday", app: "Notes", kind: .text, style: .light, minutesAgo: 48, pinned: true),
        ]
    }
}

/// A smoke shot of the closed notch: Claude Code working, with its context ring.
@MainActor
@Suite(.serialized)
struct WebsiteShotsClosedSmokeTests {
    @Test func claudeContext() async throws {
        guard let output = WebsiteShots.output else { return }
        let island = try WebsiteIsland()
        let claudeSettings = ClaudeSettings(defaults: try WebsiteShots.defaults())
        let usage = ClaudeUsageStore()
        let monitor = ClaudeLiveMonitor(loadSessions: { [] }, loadPlan: { nil }, usage: usage)
        monitor.apply([ClaudeLiveSession(
            pid: 1, sessionID: "s1", cwd: "/Users/sam/aurora-web", status: .busy, name: nil, updatedAt: Date(),
            context: ClaudeContextUsage(tokens: 184_000, window: 1_000_000, model: "claude-opus-5-5")
        )])
        let attention = ClaudeAttention(monitor: monitor, usage: usage, settings: claudeSettings)
        attention.recompute()
        island.center.register(ClaudeClosedActivity(monitor: monitor, settings: claudeSettings, attention: attention))
        try await island.renderClosed(to: output.appendingPathComponent("smoke-closed-claude.png"))
    }
}
