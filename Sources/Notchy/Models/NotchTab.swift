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
        case .clipboard: "doc.on.clipboard"
        }
    }

    /// Height of the open island's content box (header included), before the 12-pt bottom
    /// inset. Every tab keeps Home's height so switching tabs never resizes the island; only
    /// Stats grows, and only for its extra rows of graphs.
    var openHeight: CGFloat { Self.standardOpenHeight }

    static let standardOpenHeight: CGFloat = 200

    /// The open island widens as more tabs are shown so the icon row never crowds the notch.
    static func minimumOpenWidth(forTabCount count: Int) -> CGFloat {
        if count >= 7 { return 850 }
        if count >= 6 { return 770 }
        if count >= 5 { return 690 }
        return 640
    }

    static let maximumOpenWidth: CGFloat = 900
    static let defaultOpenWidth: CGFloat = 640
    /// Horizontal inset added on each side of the content box while open.
    static let openHorizontalInset: CGFloat = 12
    /// Inset added below the content box while open.
    static let openBottomInset: CGFloat = 12
}
