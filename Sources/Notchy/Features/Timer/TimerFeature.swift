import Combine
import SwiftUI

/// Puts the running timer on the closed notch through the island's live-activity chain.
@MainActor
final class TimerClosedActivity: ClosedLiveActivity {
    let activityID = "timer"
    let priority = ClosedActivityPriority.timer
    private let manager: TimerManager
    private let settings: TimerSettings

    init(manager: TimerManager = .shared, settings: TimerSettings = .shared) {
        self.manager = manager
        self.settings = settings
    }

    var isActivityVisible: Bool { TimerLiveActivityView.isPresentable(manager: manager, settings: settings) }

    /// The countdown text and the transient name label change the wing widths, so every
    /// change of the timer or its settings re-evaluates the island.
    var activityDidChange: AnyPublisher<Void, Never> {
        Publishers.Merge(
            manager.objectWillChange.map { _ in () },
            settings.objectWillChange.map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        layout(in: context)?.leftWingWidth ?? 0
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        layout(in: context)?.rightWingWidth ?? 0
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(TimerLiveActivityView(notchWidth: 0, height: context.outerHeight, isHovering: context.isHovering, part: .left, manager: manager, settings: settings))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(TimerLiveActivityView(notchWidth: 0, height: context.outerHeight, isHovering: context.isHovering, part: .right, manager: manager, settings: settings))
    }

    private func layout(in context: ClosedActivityContext) -> TimerLiveActivityLayout? {
        TimerLiveActivityLayout.current(
            collapsedHeight: context.outerHeight,
            isHovering: context.isHovering,
            manager: manager,
            settings: settings
        )
    }
}

@MainActor
enum TimerFeature {
    private static var activity: TimerClosedActivity?

    static func start() {
        let activity = TimerClosedActivity()
        self.activity = activity
        IslandActivityCenter.shared.register(activity)
        SettingsSectionRegistry.shared.register(.timer, id: "timer") { TimerSettingsSection() }
    }

    static func stop() {
        if let activity { IslandActivityCenter.shared.unregister(id: activity.activityID) }
        activity = nil
        TimerManager.shared.stop()
    }
}
