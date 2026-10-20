import Foundation

/// The tabs the open island can show, in display order. Switching to a later tab slides the
/// content in from the trailing edge, switching back slides it in from the leading edge.
enum NotchTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case shelf
    case timer
    case stats
    case notes
    case face
    case claude
    case clipboard

    var id: Self { self }

    var label: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .timer: "Timer"
        case .stats: "Stats"
        case .notes: "Notes"
        case .face: "Face Check"
        case .claude: "AI tools"
        case .clipboard: "Clipboard"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.fill"
        case .timer: "timer"
        case .stats: "chart.xyaxis.line"
        case .notes: "note.text"
        case .face: "faceid"
        case .claude: "asterisk"
        case .clipboard: "doc.on.clipboard.fill"
        }
    }

    /// Height of the open island's content box (header included), before the 12-pt bottom
    /// inset. Every tab keeps Home's height so switching tabs never resizes the island; only
    /// Stats grows, and only for its extra rows of graphs.
    var openHeight: CGFloat { Self.standardOpenHeight }

    /// The open island's content is laid out at its design size and drawn at this scale, so
    /// every widget keeps its proportions in the compact island. The header is not scaled: it
    /// has to cover the hardware notch.
    static let contentScale: CGFloat = 0.805
    /// The content height (below a 32-pt header) the tabs are designed for.
    static let designContentHeight: CGFloat = 148
    /// 32-pt header plus the design content height at `contentScale`.
    static let standardOpenHeight: CGFloat = 32 + (designContentHeight * contentScale).rounded()

    /// The open island widens as more tabs are shown so the icon row never crowds the notch.
    static func minimumOpenWidth(forTabCount count: Int) -> CGFloat {
        let design: CGFloat
        if count >= 8 { design = 820 } else if count >= 7 { design = 760 } else if count >= 6 { design = 700 } else if count >= 5 { design = 660 } else { design = 640 }
        return atContentScale(design)
    }

    /// Widths are designed at full size and drawn at `contentScale`, like the content.
    static let maximumOpenWidth: CGFloat = atContentScale(900)
    static let defaultOpenWidth: CGFloat = atContentScale(640)

    static func atContentScale(_ designWidth: CGFloat) -> CGFloat {
        (designWidth * contentScale).rounded()
    }
    /// Horizontal inset added on each side of the content box while open.
    static let openHorizontalInset: CGFloat = 12
    /// Inset added below the content box while open.
    static let openBottomInset: CGFloat = 12
}
