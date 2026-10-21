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
            clip("Lunch moved to 1:30, same place.", app: "Messages", kind: .text, style: .light, minutesAgo: 2.22, pinned: true),
            clip("https://notchyy.vercel.app", app: "Safari", kind: .link, style: .teal, minutesAgo: 6.6, urlTitle: "Notchy – Your notch, finally useful"),
            clip("#E46642", app: "Figma", kind: .color, style: .blue, minutesAgo: 9.37),
            clip("let island = Notch(open: .home)", app: "Xcode", kind: .code, style: .dark, minutesAgo: 14.75),
            clip("Meet at the studio, 3rd floor", app: "Messages", kind: .text, style: .dark, minutesAgo: 27.4),
            clip("Ship the update before Friday", app: "Notes", kind: .text, style: .light, minutesAgo: 48.12, pinned: true),
        ]
    }
}
