import Combine
import Foundation
import SwiftUI
import Testing
@testable import Notchy

// MARK: - Fixtures

private let work = CalendarSource(
    accountName: "iCloud",
    id: "cal-work",
    title: "Work",
    color: CalendarColor(red: 0.2, green: 0.4, blue: 0.9),
    isSubscribed: false,
    isReminderList: false
)

private let todo = CalendarSource(
    accountName: "iCloud",
    id: "list-todo",
    title: "To Do",
    color: CalendarColor(red: 0.9, green: 0.5, blue: 0.1),
    isSubscribed: false,
    isReminderList: true
)

private func event(
    _ id: String,
    start: Date,
    minutes: Double = 30,
    allDay: Bool = false,
    conference: URL? = nil
) -> CalendarEntry {
    CalendarEntry(
        itemIdentifier: id,
        start: start,
        end: start.addingTimeInterval(minutes * 60),
        title: id,
        isAllDay: allDay,
        kind: .event(.accepted),
        calendar: work,
        conferenceURL: conference
    )
}

private func reminder(_ id: String, due: Date, completed: Bool = false, allDay: Bool = false) -> CalendarEntry {
    CalendarEntry(
        itemIdentifier: id,
        start: due,
        end: Calendar.current.dateInterval(of: .day, for: due)?.end ?? due,
        title: id,
        isAllDay: allDay,
        kind: .reminder(completed: completed),
        calendar: todo
    )
}

private func makeDefaults() -> UserDefaults {
    let suite = "CalendarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let noon: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 15
    components.hour = 12
    return Calendar.current.date(from: components)!
}()

// MARK: - Filtering and auto-scroll

struct CalendarFilterTests {
    @Test func hidesCompletedRemindersAndAllDayEventsButKeepsAllDayReminders() {
        let entries = [
            event("meeting", start: noon),
            event("holiday", start: Calendar.current.startOfDay(for: noon), minutes: 1440, allDay: true),
            reminder("done", due: noon, completed: true),
            reminder("open-all-day", due: Calendar.current.startOfDay(for: noon), allDay: true)
        ]
        let visible = CalendarEventFilter.visibleEntries(entries, hideCompletedReminders: true, hideAllDayEvents: true)
        #expect(visible.map(\.title) == ["meeting", "open-all-day"])

        let everything = CalendarEventFilter.visibleEntries(entries, hideCompletedReminders: false, hideAllDayEvents: false)
        #expect(everything.count == 4)
    }

    @Test func splitSortsAllDayAndTimedByStart() {
        let later = event("later", start: noon.addingTimeInterval(3600))
        let earlier = event("earlier", start: noon)
        let allDay = event("all-day", start: Calendar.current.startOfDay(for: noon), minutes: 1440, allDay: true)
        let parts = CalendarEventFilter.split([later, allDay, earlier])
        #expect(parts.allDay.map(\.title) == ["all-day"])
        #expect(parts.timed.map(\.title) == ["earlier", "later"])
    }

    @Test func scrollTargetPrefersRunningConferenceThenRunningThenNextThenLast() {
        let zoom = URL(string: "https://zoom.us/j/123")!
        let running = event("running", start: noon.addingTimeInterval(-600), minutes: 60)
        let call = event("call", start: noon.addingTimeInterval(-300), minutes: 60, conference: zoom)
        let next = event("next", start: noon.addingTimeInterval(1800))
        let past = event("past", start: noon.addingTimeInterval(-7200))

        #expect(CalendarEventFilter.scrollTarget(in: [past, running, call, next], at: noon)?.title == "call")
        #expect(CalendarEventFilter.scrollTarget(in: [past, running, next], at: noon)?.title == "running")
        #expect(CalendarEventFilter.scrollTarget(in: [past, next], at: noon)?.title == "next")
        #expect(CalendarEventFilter.scrollTarget(in: [past], at: noon)?.title == "past")
        #expect(CalendarEventFilter.scrollTarget(in: [], at: noon) == nil)
    }

    @Test func remindersCountAsRunningForAnHour() {
        let due = reminder("pay", due: noon.addingTimeInterval(-50 * 60))
        let stale = reminder("old", due: noon.addingTimeInterval(-61 * 60))
        #expect(due.isActive(at: noon))
        #expect(!stale.isActive(at: noon))
        #expect(CalendarEventFilter.scrollTarget(in: [stale, due], at: noon)?.title == "pay")
    }

    @Test func scrollReferenceIsNowForTodayAndMidnightOtherwise() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: noon)!
        #expect(CalendarEventFilter.scrollReference(for: noon, now: noon) == noon)
        #expect(CalendarEventFilter.scrollReference(for: tomorrow, now: noon) == Calendar.current.startOfDay(for: tomorrow))
    }

    @Test func entryIDsAreUniquePerOccurrence() {
        let first = event("standup", start: noon)
        let second = event("standup", start: noon.addingTimeInterval(3600))
        #expect(first.itemIdentifier == second.itemIdentifier)
        #expect(first.id != second.id)
    }

    @Test func conferenceJoinableFromFifteenMinutesBefore() {
        let call = event("call", start: noon)
        #expect(!call.isJoinable(at: noon.addingTimeInterval(-16 * 60)))
        #expect(call.isJoinable(at: noon.addingTimeInterval(-15 * 60)))
        #expect(call.status(at: noon.addingTimeInterval(60)) == .inProgress)
        #expect(call.status(at: noon.addingTimeInterval(-60)) == .upcoming)
        #expect(call.status(at: noon.addingTimeInterval(31 * 60)) == .ended)
    }
}

// MARK: - Conference providers

struct ConferenceProviderTests {
    @Test func detectsProvidersFromHosts() {
        let cases: [(String, ConferenceProvider)] = [
            ("https://us02web.zoom.us/j/1", .zoom),
            ("https://teams.microsoft.com/l/meetup-join/x", .teams),
            ("https://meet.google.com/abc-defg-hij", .meet),
            ("https://acme.webex.com/meet/x", .webex),
            ("https://facetime.apple.com/join#v=1", .facetime),
            ("https://global.gotomeeting.com/join/1", .goToMeeting),
            ("https://bluejeans.com/123", .blueJeans),
            ("https://whereby.com/room", .whereby),
            ("https://meet.jit.si/room", .jitsi),
            ("https://discord.gg/abc", .discord),
            ("https://example.com/call", .generic)
        ]
        for (link, expected) in cases {
            #expect(ConferenceProvider.detect(from: URL(string: link)!) == expected, "\(link)")
        }
    }

    @Test func providerColoursMatchAtoll() {
        #expect(ConferenceProvider.zoom.brandColor == CalendarColor(red: 0.16, green: 0.52, blue: 0.95))
        #expect(ConferenceProvider.meet.brandColor == CalendarColor(red: 0.0, green: 0.65, blue: 0.42))
        #expect(ConferenceProvider.discord.brandColor == CalendarColor(red: 0.35, green: 0.39, blue: 0.98))
        #expect(ConferenceProvider.generic.brandColor == nil)
    }

    @Test func findsConferenceLinkInLocationThenNotes() {
        let url = ConferenceProvider.conferenceURL(
            url: URL(string: "https://example.com/agenda"),
            location: "Room 4",
            notes: "Agenda: https://example.com/doc\nJoin: https://meet.google.com/abc-defg-hij"
        )
        #expect(url?.host == "meet.google.com")
        #expect(ConferenceProvider.conferenceURL(url: nil, location: "Desk", notes: nil) == nil)
    }

    @Test func nativeSchemesExceptZoom() {
        let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/x")!
        #expect(ConferenceProvider.teams.launchURL(for: teams).scheme == "msteams")
        let zoom = URL(string: "https://zoom.us/j/1")!
        #expect(ConferenceProvider.zoom.launchURL(for: zoom) == zoom)
    }
}

// MARK: - App links

struct CalendarAppLinkTests {
    @Test func appleCalendarLinksNameRecurringOccurrences() {
        let single = event("ABC", start: noon)
        #expect(CalendarAppLink.url(for: single, opener: .appleCalendar)?.absoluteString
            == "ical://ekevent/ABC?method=show&options=more")

        let recurring = CalendarEntry(
            itemIdentifier: "ABC",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1800),
            title: "Standup",
            calendar: work,
            hasRecurrenceRules: true
        )
        #expect(CalendarAppLink.url(for: recurring, opener: .appleCalendar)?.absoluteString
            == "ical://ekevent/1970-01-01T00:00:00+0000/ABC?method=show&options=more")
    }

    @Test func remindersAlwaysOpenInReminders() {
        let task = reminder("R1", due: noon)
        #expect(CalendarAppLink.url(for: task, opener: .fantastical(.mini))?.absoluteString
            == "x-apple-reminderkit://remcdreminder/R1")
    }

    @Test func fantasticalAndNotionLinks() {
        let meeting = event("E1", start: noon)
        let fantastical = CalendarAppLink.url(for: meeting, opener: .fantastical(.calendar))?.absoluteString
        #expect(fantastical == "x-fantastical3://show/calendar/2026-10-15")
        let notion = CalendarAppLink.url(for: meeting, opener: .notionCalendar)
        #expect(notion?.scheme == "cron")
        #expect(notion?.host == "showEvent")
    }
}

// MARK: - Date strip and month grid

struct CalendarDateMathTests {
    @Test func dayStripSpansAWeekBackAndTwoWeeksAhead() {
        let strip = CalendarDayStrip()
        #expect(strip.dayCount == 22)
        #expect(strip.itemCount == 26)
        #expect(strip.isSpacer(0) && strip.isSpacer(1) && !strip.isSpacer(2))
        #expect(strip.isSpacer(24) && !strip.isSpacer(23))

        let today = Calendar.current.startOfDay(for: noon)
        let todayIndex = strip.index(of: noon, today: noon)
        #expect(todayIndex == 9)
        #expect(strip.day(at: todayIndex, today: noon) == today)
        #expect(strip.day(at: 2, today: noon) == Calendar.current.date(byAdding: .day, value: -7, to: today))
        let farFuture = Calendar.current.date(byAdding: .day, value: 40, to: noon)!
        #expect(strip.index(of: farFuture, today: noon) == 23)
    }

    @Test func monthGridCoversWholeWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let days = CalendarMonthGrid.days(for: october, calendar: calendar)
        #expect(days.count % 7 == 0)
        #expect(calendar.component(.weekday, from: days.first!) == 1)
        #expect(calendar.component(.weekday, from: days.last!) == 7)
        #expect(days.contains(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!))
        #expect(days.contains(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!))
    }

    @Test func weekdayInitialsStartOnFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        let initials = CalendarMonthGrid.weekdayInitials(calendar: calendar)
        #expect(initials == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test func standaloneHeightFollowsAtoll() {
        #expect(CalendarLayout.standaloneHeight(openHeight: 200, closedHeight: 32) == 132)
        #expect(CalendarLayout.standaloneHeight(openHeight: 150, closedHeight: 32) == 130)
    }

    @Test func luminanceAdjustmentScalesTowardTarget() {
        let dark = CalendarColor(red: 0.1, green: 0.1, blue: 0.4)
        let lifted = dark.adjustedToLuminance(0.7)
        #expect(lifted.luminance > dark.luminance)
        #expect(lifted.blue <= 1)
        let black = CalendarColor(red: 0, green: 0, blue: 0)
        #expect(black.adjustedToLuminance(0.7) == CalendarColor(red: 0.7, green: 0.7, blue: 0.7))
    }
}

// MARK: - Settings

@MainActor
struct CalendarSettingsTests {
    @Test func defaultsMatchAtoll() {
        let settings = CalendarSettings(defaults: makeDefaults())
        #expect(settings.showCalendar)
        #expect(settings.hideCompletedReminders)
        #expect(!settings.hideAllDayEvents)
        #expect(!settings.showFullEventTitles)
        #expect(settings.autoScrollToNextEvent)
        #expect(settings.calendarSelection == .all)
        #expect(settings.enableReminderLiveActivity)
        #expect(settings.reminderPresentationStyle == .ring)
        #expect(settings.reminderLeadTime == 5)
        #expect(settings.reminderSneakPeekDuration == 5)
        #expect(!settings.enableThirdPartyCalendarApp)
        #expect(settings.opener == .appleCalendar)
    }

    @Test func persistsUnderCalendarKeys() {
        let defaults = makeDefaults()
        let settings = CalendarSettings(defaults: defaults)
        settings.showCalendar = false
        settings.reminderPresentationStyle = .digital
        settings.reminderLeadTime = 90
        settings.calendarSelection = .selected(["a", "b"])
        settings.enableThirdPartyCalendarApp = true
        settings.selectedCalendarApp = .notionCalendar

        #expect(defaults.object(forKey: "calendar.showCalendar") as? Bool == false)
        #expect(defaults.string(forKey: "calendar.reminderPresentationStyle") == "Digital")
        #expect(settings.reminderLeadTime == 60)

        let reloaded = CalendarSettings(defaults: defaults)
        #expect(!reloaded.showCalendar)
        #expect(reloaded.reminderPresentationStyle == .digital)
        #expect(reloaded.reminderLeadTime == 60)
        #expect(reloaded.calendarSelection == .selected(["a", "b"]))
        #expect(reloaded.opener == .notionCalendar)
    }

    @Test func selectionCollapsesBackToAll() {
        let all: Set<String> = ["a", "b", "c"]
        let afterUntick = CalendarSettings.updatedSelection(.all, setting: ["a"], selected: false, allIDs: all)
        #expect(afterUntick == .selected(["b", "c"]))
        let afterRetick = CalendarSettings.updatedSelection(afterUntick, setting: ["a"], selected: true, allIDs: all)
        #expect(afterRetick == .all)
        let afterEmpty = CalendarSettings.updatedSelection(.selected(["b"]), setting: ["b"], selected: false, allIDs: all)
        #expect(afterEmpty == .all)
    }
}

// MARK: - Reminder live activity

struct ReminderScheduleTests {
    @Test func buildsEntriesForFutureItemsOnly() {
        let events = [
            event("past", start: noon.addingTimeInterval(-60)),
            event("soon", start: noon.addingTimeInterval(10 * 60)),
            event("all-day", start: noon.addingTimeInterval(3600), allDay: true),
            reminder("done", due: noon.addingTimeInterval(20 * 60), completed: true),
            reminder("todo", due: noon.addingTimeInterval(5 * 60))
        ]
        let entries = ReminderSchedule.entries(
            from: events,
            leadMinutes: 5,
            now: noon,
            hideAllDayEvents: true,
            hideCompletedReminders: true
        )
        #expect(entries.map(\.event.title) == ["todo", "soon"])
        #expect(entries.first?.triggerDate == noon)
        #expect(entries.first?.leadTime == 300)
    }

    @Test func countdownTexts() {
        let entry = ReminderEntry(event: event("x", start: noon.addingTimeInterval(299)), triggerDate: noon, leadTime: 300)
        #expect(ReminderSchedule.digitalText(entry, now: noon) == "04:59")
        #expect(ReminderSchedule.minutesText(entry, now: noon) == "in 5 min")
        #expect(ReminderSchedule.minutesText(entry, now: noon.addingTimeInterval(290)) == "in 1 min")
        #expect(abs(ReminderSchedule.progress(entry, now: noon) - 1.0 / 300) < 0.0001)
        #expect(ReminderSchedule.isCritical(entry, now: noon.addingTimeInterval(295), window: 5))
        #expect(!ReminderSchedule.isCritical(entry, now: noon, window: 5))
    }

    @Test func sneakPeekText() {
        let entry = ReminderEntry(event: event("Standup", start: noon.addingTimeInterval(300)), triggerDate: noon, leadTime: 300)
        let text = ReminderSchedule.sneakPeekText(entry, now: noon, window: 5)
        #expect(text.hasPrefix("Standup • in 5 min • "))
        #expect(ReminderSchedule.sneakPeekText(entry, now: noon.addingTimeInterval(297), window: 5) == "Standup • now")
    }

    @Test func wingMetricsFollowAtoll() {
        #expect(ReminderWingMetrics.leftWidth(closedHeight: 32) == 42)
        #expect(ReminderWingMetrics.ringDiameter(closedHeight: 32) == 20)
        #expect(ReminderWingMetrics.ringDiameter(closedHeight: 24) == 16)
        #expect(ReminderWingMetrics.ringDiameter(closedHeight: 40) == 22)
        #expect(ReminderWingMetrics.rightWidth(style: .ring, closedHeight: 32, entry: nil, now: noon) == 36)
        #expect(ReminderWingMetrics.rightWidth(style: .digital, closedHeight: 32, entry: nil, now: noon) >= 92)
        #expect(ReminderWingMetrics.rightWidth(style: .minutes, closedHeight: 32, entry: nil, now: noon) >= 104)
    }

    /// Atoll's music-paired reminder sizes, measured against the wing content height
    /// (closed height - 12 at rest, the full closed height while hovered).
    @Test func musicSupplementMetricsFollowAtoll() {
        // 32-pt notch at rest: content 20 -> ring 16 in a 26-pt frame.
        #expect(ReminderMusicSupplement.ringFrameWidth(notchHeight: 20) == 26)
        // Hovered: content 32 -> ring 20 in a 26-pt frame (20 + 4 < 26).
        #expect(ReminderMusicSupplement.ringFrameWidth(notchHeight: 32) == 26)
        // Taller notch: ring capped at 22 -> 26.
        #expect(ReminderMusicSupplement.ringFrameWidth(notchHeight: 40) == 26)
        #expect(ReminderMusicSupplement.digitalFrameWidth(for: "04:59") >= 76)
        #expect(ReminderMusicSupplement.minutesFrameWidth(for: "in 5 min") >= 88)
        #expect(ReminderMusicSupplement.badgeSize(artworkSize: 20) == 13)
        #expect(abs(ReminderMusicSupplement.badgeSize(artworkSize: 50) - 18) < 0.0001)
        #expect(ReminderMusicSupplement.badgeOffset(badgeSize: 20) == CGSize(width: 4, height: 5))
    }
}

@MainActor
struct ReminderLiveActivityModelTests {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeModel(clock: Clock, peeks: @escaping (SneakPeek) -> Void) -> (ReminderLiveActivityModel, CalendarSettings) {
        let settings = CalendarSettings(defaults: makeDefaults())
        let model = ReminderLiveActivityModel(
            settings: settings,
            events: Empty().eraseToAnyPublisher(),
            clock: { clock.now },
            sneakPeek: peeks,
            usesTimers: false
        )
        return (model, settings)
    }

    @Test func activatesInLeadWindowAndAdvancesAtStart() {
        let clock = Clock(noon)
        var peeks: [SneakPeek] = []
        let (model, _) = makeModel(clock: clock) { peeks.append($0) }
        let first = event("First", start: noon.addingTimeInterval(10 * 60))
        let second = event("Second", start: noon.addingTimeInterval(12 * 60))
        model.apply(events: [first, second])

        #expect(model.activeReminder == nil)
        #expect(!model.isActivityVisible)

        clock.now = noon.addingTimeInterval(5 * 60)
        model.evaluate(at: clock.now)
        #expect(model.activeReminder?.event.title == "First")
        #expect(model.isActivityVisible)
        #expect(peeks.count == 1)
        #expect(peeks.first?.kind == .reminder)
        #expect(peeks.first?.systemImage == ReminderSchedule.standardSymbol)

        // Inside the final 5 s the critical peek fires once.
        clock.now = noon.addingTimeInterval(10 * 60 - 4)
        model.evaluate(at: clock.now)
        model.evaluate(at: clock.now.addingTimeInterval(1))
        #expect(peeks.count == 2)
        #expect(peeks.last?.systemImage == ReminderSchedule.criticalSymbol)

        // At the start it moves on to the next entry, already inside its window.
        clock.now = noon.addingTimeInterval(10 * 60)
        model.evaluate(at: clock.now)
        #expect(model.activeReminder?.event.title == "Second")
        #expect(peeks.count == 3)
    }

    @Test func disablingHidesTheActivity() {
        let clock = Clock(noon)
        let (model, settings) = makeModel(clock: clock) { _ in }
        model.apply(events: [event("Soon", start: noon.addingTimeInterval(60))])
        #expect(model.isActivityVisible)
        settings.enableReminderLiveActivity = false
        model.evaluate(at: noon)
        #expect(!model.isActivityVisible)
        #expect(model.activeReminder == nil)
    }

    @Test func emitsChangesWhenVisibilityChanges() {
        let clock = Clock(noon)
        let (model, _) = makeModel(clock: clock) { _ in }
        var changes = 0
        let subscription = model.activityDidChange.sink { changes += 1 }
        model.apply(events: [event("Soon", start: noon.addingTimeInterval(60))])
        #expect(changes >= 1)
        let afterShow = changes
        model.evaluate(at: noon.addingTimeInterval(1))
        #expect(changes == afterShow)
        model.evaluate(at: noon.addingTimeInterval(61))
        #expect(changes > afterShow)
        #expect(!model.isActivityVisible)
        subscription.cancel()
    }
}

// MARK: - Date strip event days

struct CalendarEventDaysTests {
    private let calendar = Calendar.current
    private var firstDay: Date { calendar.startOfDay(for: noon) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: firstDay)! }

    @Test func marksEachDayAnEntryTouchesWithItsEarliestColour() {
        let late = event("late", start: day(0).addingTimeInterval(18 * 3600))
        let early = reminder("early", due: day(0).addingTimeInterval(8 * 3600))
        // Two all-day days: midnight to midnight two days later.
        let trip = CalendarEntry(itemIdentifier: "trip", start: day(2), end: day(4), title: "trip", isAllDay: true, calendar: work)
        let days = CalendarEventFilter.eventDays([late, early, trip], from: firstDay, dayCount: 5)
        #expect(days[day(0)] == todo.color)
        #expect(days[day(1)] == nil)
        #expect(days[day(2)] == work.color)
        #expect(days[day(3)] == work.color)
        #expect(days[day(4)] == nil, "an all-day event ends at midnight, exclusive")
    }

    @Test func ignoresEntriesOutsideTheStrip() {
        let before = event("before", start: day(-1).addingTimeInterval(3600))
        let after = event("after", start: day(3).addingTimeInterval(3600))
        let days = CalendarEventFilter.eventDays([before, after], from: firstDay, dayCount: 3)
        #expect(days.isEmpty)
    }

    @Test func overnightEventCountsOnBothDays() {
        let overnight = event("overnight", start: day(0).addingTimeInterval(23 * 3600), minutes: 120)
        let days = CalendarEventFilter.eventDays([overnight], from: firstDay, dayCount: 3)
        #expect(Set(days.keys) == [day(0), day(1)])
    }

    @MainActor @Test func stripNumbersUseEventColourExceptToday() {
        #expect(CalendarDayStripPicker.numberStyle(isToday: true, isSelected: false, eventColor: .red) == .white)
        #expect(CalendarDayStripPicker.numberStyle(isToday: false, isSelected: false, eventColor: .red) == .red)
        #expect(CalendarDayStripPicker.numberStyle(isToday: false, isSelected: true, eventColor: nil) == .white)
    }
}
