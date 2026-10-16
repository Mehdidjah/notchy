import Combine
import CoreGraphics

/// Which layout the Notes tab shows; each one asks for its own open-island height.
enum NotesLayoutMode: String, Equatable, Sendable {
    case list
    case split
    case editor

    /// Atoll's open heights for the Notes tab (header included): list 240, split 260, editor 320.
    var preferredHeight: CGFloat {
        switch self {
        case .list: 240
        case .split: 260
        case .editor: 320
        }
    }
}

/// Published Notes layout for the host: the island grows to `preferredHeight` while the Notes
/// tab is selected, animated with `.easeInOut(duration: 0.25)` like Atoll.
@MainActor
final class NotesLayoutState: ObservableObject {
    static let shared = NotesLayoutState()

    /// The Notes tab's base open height in the host (`NotchTab.notes.openHeight`).
    static let baseHeight: CGFloat = NotesLayoutMode.list.preferredHeight
    /// Atoll animates Notes height changes with this curve.
    static let heightAnimationDuration: Double = 0.25

    @Published private(set) var mode: NotesLayoutMode = .list
    @Published private(set) var preferredHeight: CGFloat = NotesLayoutMode.list.preferredHeight
    /// True while the pointer is over the notes list or editor. Atoll suppresses the
    /// swipe-up-to-close gesture then, so scrolling the notes never folds the island away.
    @Published private(set) var suppressesCloseGesture = false

    init() {}

    /// Height to add on top of the Notes tab's base height.
    var extraHeight: CGFloat { max(0, preferredHeight - Self.baseHeight) }

    func setMode(_ newMode: NotesLayoutMode) {
        if mode != newMode { mode = newMode }
        let height = newMode.preferredHeight
        if preferredHeight != height { preferredHeight = height }
    }

    /// Layout used while no note is open: split when the clipboard is shown beside the notes.
    func setResting(showsClipboard: Bool) {
        setMode(showsClipboard ? .split : .list)
    }

    func setPointerOverNotes(_ inside: Bool) {
        if suppressesCloseGesture != inside { suppressesCloseGesture = inside }
    }
}
