#if DEBUG
import Foundation

extension Clip {
    static let debugPreviewItems: [Clip] = [
        Clip(
            title: "A clipboard that stays one step ahead.",
            value: "A clipboard that stays one step ahead.",
            detail: "Safari · now",
            kind: .text,
            style: .light,
            symbolName: "doc.text.fill",
            isPinned: true
        ),
        Clip(
            title: "developer.apple.com/design/human-interface-guidelines",
            value: "https://developer.apple.com/design/human-interface-guidelines",
            detail: "Safari · 5 min ago",
            kind: .link,
            style: .teal,
            symbolName: "link",
            isPinned: true
        ),
        Clip(
            title: "Minneapolis 55410,\n2941 Rocket Drive\nUnited States",
            value: "Minneapolis 55410, 2941 Rocket Drive, United States",
            detail: "Chrome · 19 min ago",
            kind: .text,
            style: .dark,
            symbolName: "mappin.and.ellipse"
        ),
        Clip(
            title: "#0080FF",
            value: "#0080FF",
            detail: "Mail · 35 min ago",
            kind: .color,
            style: .blue,
            symbolName: "paintpalette.fill",
            isPinned: true
        ),
        Clip(
            title: "let history = clipboard.items.reversed()",
            value: "let history = clipboard.items.reversed()",
            detail: "Xcode · 42 min ago",
            kind: .code,
            style: .dark,
            symbolName: "chevron.left.forwardslash.chevron.right"
        )
    ]
}
#endif
