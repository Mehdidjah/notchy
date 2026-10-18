import Combine
import SwiftUI

/// What the Home tab shows. Feature modules flip these flags; the Home tab lays the shown
/// features out as a row of cards beside its own (`HomeWidgetSettings`).
@MainActor
final class HomeLayoutState: ObservableObject {
    static let shared = HomeLayoutState()

    /// Set by the media feature: a player has an active session (or auto-hide is off).
    @Published var showsMediaPlayer = false
    /// Set by the calendar feature: the calendar is enabled.
    @Published var showsCalendar = false
    /// Set by the mirror feature: the camera mirror is enabled.
    @Published var showsMirror = false
    /// Extra height the Home tab asks for. No Home feature uses it: every tab keeps Home's height.
    @Published var extraHeight: CGFloat = 0

    init() {}

    var hasContent: Bool { showsMediaPlayer || showsCalendar || showsMirror }
}
