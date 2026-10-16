import AppKit
import EventKit

/// Owns the EventKit store and does every EventKit call off the main thread. Results come
/// back as Sendable value types.
actor CalendarEventService {
    private let store = EKEventStore()

    init() {}

    nonisolated static func status(for type: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: type)
    }

    /// Full access is the only status that can read events on macOS 14; the legacy
    /// "authorized" value shares its raw value.
    nonisolated static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    /// Shows the system prompt when the user has not decided yet.
    func requestFullAccess(to type: EKEntityType) async -> Bool {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let completion: @Sendable (Bool, (any Error)?) -> Void = { granted, _ in
                continuation.resume(returning: granted)
            }
            switch type {
            case .event:
                store.requestFullAccessToEvents(completion: completion)
            case .reminder:
                store.requestFullAccessToReminders(completion: completion)
            @unknown default:
                continuation.resume(returning: false)
            }
        }
        if granted { store.refreshSourcesIfNecessary() }
        return granted
    }

    /// Calendars and reminder lists the app may read.
    func calendars() -> [CalendarSource] {
        var calendars: [EKCalendar] = []
        if Self.isGranted(Self.status(for: .event)) {
            calendars.append(contentsOf: store.calendars(for: .event))
        }
        if Self.isGranted(Self.status(for: .reminder)) {
            calendars.append(contentsOf: store.calendars(for: .reminder))
        }
        return calendars.map(Self.source(from:))
    }

    /// Events overlapping `[start, end)` and reminders due inside it, sorted by start.
    /// `calendarIDs` nil means every calendar. Completed reminders are only fetched when asked
    /// for; the incomplete-only query is far cheaper on large reminder lists.
    func entries(
        from start: Date,
        to end: Date,
        calendarIDs: Set<String>?,
        includeCompletedReminders: Bool
    ) async -> [CalendarEntry] {
        var entries: [CalendarEntry] = []

        if Self.isGranted(Self.status(for: .event)) {
            let calendars = store.calendars(for: .event).filter { calendar in
                calendarIDs.map { $0.contains(calendar.calendarIdentifier) } ?? true
            }
            if !calendars.isEmpty {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
                entries.append(contentsOf: store.events(matching: predicate).compactMap(Self.entry(from:)))
            }
        }

        if Self.isGranted(Self.status(for: .reminder)) {
            let lists = store.calendars(for: .reminder).filter { list in
                calendarIDs.map { $0.contains(list.calendarIdentifier) } ?? true
            }
            if !lists.isEmpty {
                let predicate = includeCompletedReminders
                    ? store.predicateForReminders(in: lists)
                    : store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: lists)
                entries.append(contentsOf: await reminders(matching: predicate, from: start, to: end))
            }
        }

        return entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset : lhs.element.start < rhs.element.start
            }
            .map(\.element)
    }

    /// Ticks or unticks a reminder. Returns whether the change was saved.
    func setReminderCompleted(itemIdentifier: String, completed: Bool) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: itemIdentifier) as? EKReminder else { return false }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func reminders(matching predicate: NSPredicate, from start: Date, to end: Date) async -> [CalendarEntry] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[CalendarEntry], Never>) in
            _ = store.fetchReminders(matching: predicate) { @Sendable reminders in
                let entries = (reminders ?? []).compactMap { reminder -> CalendarEntry? in
                    guard let entry = Self.entry(from: reminder), entry.start >= start, entry.start <= end else {
                        return nil
                    }
                    return entry
                }
                continuation.resume(returning: entries)
            }
        }
    }

    // MARK: - Conversion

    static func source(from calendar: EKCalendar) -> CalendarSource {
        let source: EKSource? = calendar.source
        let localTypes: [EKSourceType] = [.local, .subscribed, .birthdays]
        let accountName: String
        if let source, !localTypes.contains(source.sourceType) {
            accountName = source.title
        } else {
            accountName = "Other"
        }
        return CalendarSource(
            accountName: accountName,
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: calendar.color.map(CalendarColor.init) ?? .fallback,
            isSubscribed: calendar.isSubscribed || (source?.isDelegate ?? false),
            isReminderList: calendar.allowedEntityTypes.contains(.reminder)
        )
    }

    static func entry(from event: EKEvent) -> CalendarEntry? {
        guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate else {
            return nil
        }
        let kind: CalendarEntryKind
        if event.birthdayContactIdentifier != nil {
            kind = .birthday
        } else {
            let status = event.attendees?.first(where: \.isCurrentUser)?.participantStatus
            kind = .event(attendance(from: status))
        }
        return CalendarEntry(
            itemIdentifier: event.calendarItemIdentifier,
            start: start,
            end: end,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: spansWholeDays(event: event, start: start, end: end),
            kind: kind,
            calendar: source(from: calendar),
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil,
            conferenceURL: ConferenceProvider.conferenceURL(url: event.url, location: event.location, notes: event.notes)
        )
    }

    /// Reminders sit at their due time and end at the end of that day; one without a time of
    /// day counts as all-day.
    static func entry(from reminder: EKReminder) -> CalendarEntry? {
        guard let calendar = reminder.calendar,
              let due = reminder.dueDateComponents,
              let date = Calendar.current.date(from: due)
        else { return nil }
        let endOfDay = Calendar.current.dateInterval(of: .day, for: date)?.end ?? date
        return CalendarEntry(
            itemIdentifier: reminder.calendarItemIdentifier,
            start: date,
            end: endOfDay,
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: due.hour == nil,
            kind: .reminder(completed: reminder.isCompleted),
            calendar: source(from: calendar),
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: CalendarReminderPriority(eventKitPriority: reminder.priority),
            conferenceURL: nil
        )
    }

    static func attendance(from status: EKParticipantStatus?) -> CalendarAttendance {
        switch status {
        case .accepted: .accepted
        case .tentative: .maybe
        case .declined: .declined
        case .pending: .pending
        default: .unknown
        }
    }

    /// EventKit's all-day flag, or an event that runs exactly from midnight to midnight.
    private static func spansWholeDays(event: EKEvent, start: Date, end: Date) -> Bool {
        if event.isAllDay { return true }
        let calendar = Calendar.current
        guard start == calendar.startOfDay(for: start), end > start else { return false }
        return end == calendar.startOfDay(for: end)
    }
}
