import Combine
import SwiftUI

/// Entry point of the calendar feature: loads EventKit data, registers the reminder live
/// activity with the island and keeps the Home tab's calendar slot in step with the
/// "Show calendar" setting.
@MainActor
enum CalendarFeature {
    private static var subscriptions: Set<AnyCancellable> = []
    private static var isRunning = false

    static func start() {
        guard !isRunning else { return }
        isRunning = true
        let settings = CalendarSettings.shared
        CalendarStore.shared.start()
        ReminderLiveActivityModel.shared.start()
        IslandActivityCenter.shared.register(ReminderLiveActivityModel.shared)

        HomeLayoutState.shared.showsCalendar = settings.showCalendar
        settings.$showCalendar
            .removeDuplicates()
            .sink { HomeLayoutState.shared.showsCalendar = $0 }
            .store(in: &subscriptions)
    }

    static func stop() {
        guard isRunning else { return }
        isRunning = false
        subscriptions.removeAll()
        IslandActivityCenter.shared.unregister(id: ReminderLiveActivityModel.shared.activityID)
        ReminderLiveActivityModel.shared.stop()
        CalendarStore.shared.stop()
        HomeLayoutState.shared.showsCalendar = false
    }
}
