import Foundation

/// The tabs the open island can show, in Atoll's order. Switching to a later tab slides the
/// content in from the trailing edge, switching back slides it in from the leading edge.
enum NotchTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case shelf
    case timer
    case stats
    case notes
    case clipboard

    var id: Self { self }

    var label: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .timer: "Timer"
        case .stats: "Stats"
        case .notes: "Notes"
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
        case .clipboard: "doc.on.clipboard"
        }
    }

    /// Height of the open island's content box for this tab (header included), before the
    /// 12-pt bottom inset. Atoll: 200 by default, Timer 250, Notes and Clipboard 240.
    var openHeight: CGFloat {
        switch self {
        case .home: 200
        case .shelf: 200
        case .timer: 250
        case .stats: 200
        case .notes: 240
        case .clipboard: 240
        }
    }

    /// The open island widens as more tabs are shown so the icon row never crowds the notch.
    static func minimumOpenWidth(forTabCount count: Int) -> CGFloat {
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
