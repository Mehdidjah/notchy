import Combine
import SwiftUI

/// What the Home tab shows. Feature modules flip these flags; the Home tab lays itself out
/// the way Atoll does: player on the left, the compact calendar beside it, the camera mirror
/// on the right, or the standalone calendar when no player is shown.
@MainActor
final class HomeLayoutState: ObservableObject {
    static let shared = HomeLayoutState()

    /// Set by the media feature: a player has an active session (or auto-hide is off).
    @Published var showsMediaPlayer = false
    /// Set by the calendar feature: the calendar is enabled.
    @Published var showsCalendar = false
    /// Set by the mirror feature: the camera mirror is enabled.
    @Published var showsMirror = false
    /// Extra height the Home tab needs, for example an inline lyrics line (+18 in Atoll).
    @Published var extraHeight: CGFloat = 0

    init() {}

    var hasContent: Bool { showsMediaPlayer || showsCalendar || showsMirror }
}
