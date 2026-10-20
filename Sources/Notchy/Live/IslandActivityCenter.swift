import Combine
import SwiftUI

/// Geometry handed to closed-notch live activities so they can size and draw their wings.
///
/// Closed layout: a left wing, a black centre that covers the hardware notch,
/// and a right wing, all `contentHeight` tall inside an island `outerHeight` tall.
struct ClosedActivityContext: Equatable, Sendable {
    /// Height of the closed notch: the display's safe-area inset, or the menu-bar height.
    let closedHeight: CGFloat
    /// Width of the closed notch without hover: the hardware gap plus a small bleed.
    let notchWidth: CGFloat
    let isHovering: Bool
    /// Downward swipe progress, 0...20; widens the wings by half of it.
    let gestureProgress: CGFloat
    /// True on displays with a camera housing; false for the synthetic island.
    let hasHardwareNotch: Bool

    /// Height available to wing content: the full notch height while hovered, otherwise 12 pt less.
    var contentHeight: CGFloat { isHovering ? closedHeight : max(0, closedHeight - 12) }
    /// Default width of each wing: square to the content height, stretched by a swipe.
    var wingBaseWidth: CGFloat { max(0, contentHeight + max(0, gestureProgress) / 2) }
    /// Black centre that covers the hardware notch; grows 8 pt while hovered.
    var centerWidth: CGFloat { max(notchWidth + (isHovering ? NotchSilhouette.hoverSwell : 0), 96) }
    /// Overall height of the closed island while an activity is shown.
    var outerHeight: CGFloat { closedHeight + (isHovering ? NotchSilhouette.hoverSwell : 0) }
}

/// Sizes of a closed-notch activity's three columns, before the island's 14-pt side padding.
struct ClosedActivityLayout: Equatable, Sendable {
    var leftWidth: CGFloat
    var centerWidth: CGFloat
    var rightWidth: CGFloat
    var contentHeight: CGFloat
    var outerHeight: CGFloat

    var contentWidth: CGFloat { leftWidth + centerWidth + rightWidth }
}

/// Ordering of closed-notch activities; lower values win. Closed-notch chain:
/// battery HUD, inline HUD, caps lock, music, timer, reminder, recording, download, focus,
/// privacy, shelf.
enum ClosedActivityPriority {
    static let batteryHUD = 10
    static let inlineHUD = 20
    static let capsLock = 30
    static let faceCheck = 35
    static let music = 40
    static let timer = 50
    static let reminder = 60
    static let recording = 70
    static let download = 80
    static let focus = 100
    static let privacy = 110
    static let shelf = 130
}

/// A source of content for the closed notch's wings.
///
/// Feature modules implement this and register an instance with
/// `IslandActivityCenter.shared.register(_:)`. Emit on `activityDidChange` only when
/// visibility or wing sizes change; wing views observe their own models for content updates.
@MainActor
protocol ClosedLiveActivity: AnyObject {
    var activityID: String { get }
    var priority: Int { get }
    /// Whether the activity wants the closed notch right now.
    var isActivityVisible: Bool { get }
    /// Emits whenever visibility or wing sizes change.
    var activityDidChange: AnyPublisher<Void, Never> { get }
    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat
    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat
    func leftWing(in context: ClosedActivityContext) -> AnyView
    func rightWing(in context: ClosedActivityContext) -> AnyView
    /// Optional content drawn over the black centre, for example song text on displays
    /// without a camera housing.
    func centerOverlay(in context: ClosedActivityContext) -> AnyView?
    /// An activity may unfold without opening a tab. Its content reserves the camera housing.
    func expandedContent(in context: ClosedActivityContext) -> AnyView?
    func layout(in context: ClosedActivityContext) -> ClosedActivityLayout
    var suppressesAutomaticOpen: Bool { get }
    @discardableResult func handleHover(_ hovering: Bool) -> Bool
    @discardableResult func handleTap() -> Bool
}

extension ClosedLiveActivity {
    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat { context.wingBaseWidth }
    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat { context.wingBaseWidth }
    func centerOverlay(in context: ClosedActivityContext) -> AnyView? { nil }
    func expandedContent(in context: ClosedActivityContext) -> AnyView? { nil }
    var suppressesAutomaticOpen: Bool { false }
    func handleHover(_ hovering: Bool) -> Bool { false }
    func handleTap() -> Bool { false }
    func layout(in context: ClosedActivityContext) -> ClosedActivityLayout {
        ClosedActivityLayout(
            leftWidth: max(0, leftWingWidth(in: context)), centerWidth: context.centerWidth,
            rightWidth: max(0, rightWingWidth(in: context)),
            contentHeight: context.contentHeight, outerHeight: context.outerHeight
        )
    }
}

/// A short message that drops under the closed notch and folds away by itself
/// (the "sneak peek", standard style).
struct SneakPeek: Equatable, Identifiable {
    enum Kind: String, Sendable {
        case clipboard, music, timer, reminder, volume, brightness, battery, bluetooth
        case capsLock, download, focus, colorPicker, update, claude, generic
    }

    var id = UUID()
    var kind: Kind
    var systemImage: String
    var title: String
    var subtitle: String?
    /// 0...1 for level HUDs such as volume or brightness; nil for text-only peeks.
    var level: Double?
    var tint: Color?
    var duration: Duration = .milliseconds(1_500)
}

/// Shared registry of closed-notch activities and sneak-peek requests.
@MainActor
final class IslandActivityCenter: ObservableObject {
    static let shared = IslandActivityCenter()

    /// ID of the activity that currently owns the closed notch, if any.
    @Published private(set) var activeActivityID: String?
    /// Bumped whenever the winning activity or its wing sizes may have changed.
    @Published private(set) var revision = 0
    /// Sneak peeks requested by features; the island shows them when it can.
    let sneakPeekRequests = PassthroughSubject<SneakPeek, Never>()

    private var activities: [ClosedLiveActivity] = []
    private var subscriptions: [String: AnyCancellable] = [:]

    init() {}

    var registeredActivityIDs: [String] { activities.map(\.activityID) }

    /// The highest-priority visible activity.
    var activeActivity: ClosedLiveActivity? {
        activities
            .filter(\.isActivityVisible)
            .min { $0.priority < $1.priority }
    }

    func register(_ activity: ClosedLiveActivity) {
        unregister(id: activity.activityID)
        activities.append(activity)
        subscriptions[activity.activityID] = activity.activityDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.reevaluate() }
        reevaluate()
    }

    func unregister(id: String) {
        activities.removeAll { $0.activityID == id }
        subscriptions[id] = nil
        reevaluate()
    }

    /// Asks the island to show a sneak peek. It is dropped while the island is open or the
    /// pointer is on it.
    func requestSneakPeek(_ peek: SneakPeek) {
        sneakPeekRequests.send(peek)
    }

    /// Re-reads every activity; call after changing state that `activityDidChange` did not cover.
    func reevaluate() {
        let id = activeActivity?.activityID
        if id != activeActivityID { activeActivityID = id }
        revision &+= 1
    }

    /// Column sizes for the winning activity in `context`, or nil when none is visible.
    func layout(in context: ClosedActivityContext) -> ClosedActivityLayout? {
        guard let activity = activeActivity else { return nil }
        return activity.layout(in: context)
    }
}
