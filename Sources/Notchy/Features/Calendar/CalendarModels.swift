import AppKit
import SwiftUI

// MARK: - Colour

/// An sRGB colour kept as plain numbers so calendar data can move between actors.
struct CalendarColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            self = .fallback
            return
        }
        self.init(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent),
            alpha: Double(rgb.alphaComponent)
        )
    }

    /// Used when a calendar reports a colour that cannot be expressed in sRGB.
    static let fallback = CalendarColor(red: 0.56, green: 0.56, blue: 0.58)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    /// Relative luminance with the Rec. 709 weights.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Rescales the channels so the luminance lands on `target`, capping each channel at 1.
    /// Closed-notch reminder glyphs are tinted this way (factor 0.7) so dark calendar colours
    /// stay legible on black; bright colours are toned down to the same level.
    func adjustedToLuminance(_ target: Double) -> CalendarColor {
        guard (0...1).contains(target) else { return self }
        let current = luminance
        guard current > 0.0001 else {
            return CalendarColor(red: target, green: target, blue: target, alpha: alpha)
        }
        let scale = target / current
        return CalendarColor(
            red: min(red * scale, 1),
            green: min(green * scale, 1),
            blue: min(blue * scale, 1),
            alpha: alpha
        )
    }
}

/// Shared colours of the calendar UI.
enum CalendarPalette {
    /// Default accent colour (`Color.blue`).
    static let accent = Color.blue
    /// Accent background: the accent at 25 %.
    static let accentBackground = accent.opacity(0.25)
    static let secondaryText = Color(white: 0.65)
}

// MARK: - Calendars and entries

/// A calendar or reminder list.
struct CalendarSource: Identifiable, Hashable, Sendable {
    let accountName: String
    let id: String
    let title: String
    let color: CalendarColor
    let isSubscribed: Bool
    /// True for reminder lists.
    let isReminderList: Bool
}

/// The current user's response to an invitation, in sort order.
enum CalendarAttendance: Int, Comparable, Sendable {
    case accepted = 1
    case maybe = 2
    case declined = 3
    case pending = 4
    case unknown = 5

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CalendarEntryKind: Hashable, Sendable {
    case event(CalendarAttendance)
    case birthday
    case reminder(completed: Bool)

    var isReminder: Bool {
        if case .reminder = self { return true }
        return false
    }

    var isCompletedReminder: Bool {
        if case .reminder(let completed) = self { return completed }
        return false
    }
}

enum CalendarEntryStatus: Sendable {
    case upcoming
    case inProgress
    case ended
}

enum CalendarReminderPriority: Sendable {
    case high
    case medium
    case low

    /// EventKit priorities: 1–4 high, 5 medium, 6–9 low, 0 none.
    init?(eventKitPriority value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: return nil
        }
    }
}

/// An event, birthday or reminder on a day.
struct CalendarEntry: Identifiable, Hashable, Sendable {
    /// Unique per occurrence: the calendar item identifier plus the start time, so two
    /// occurrences of a repeating event on one day never collide in a list.
    let id: String
    /// EventKit's `calendarItemIdentifier`, used to open or complete the item.
    let itemIdentifier: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let kind: CalendarEntryKind
    let calendar: CalendarSource
    let hasRecurrenceRules: Bool
    let priority: CalendarReminderPriority?
    let conferenceURL: URL?

    init(
        itemIdentifier: String,
        start: Date,
        end: Date,
        title: String,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        isAllDay: Bool = false,
        kind: CalendarEntryKind = .event(.unknown),
        calendar: CalendarSource,
        hasRecurrenceRules: Bool = false,
        priority: CalendarReminderPriority? = nil,
        conferenceURL: URL? = nil
    ) {
        self.id = "\(itemIdentifier)@\(Int64(start.timeIntervalSinceReferenceDate))"
        self.itemIdentifier = itemIdentifier
        self.start = start
        self.end = end
        self.title = title
        self.location = location
        self.notes = notes
        self.url = url
        self.isAllDay = isAllDay
        self.kind = kind
        self.calendar = calendar
        self.hasRecurrenceRules = hasRecurrenceRules
        self.priority = priority
        self.conferenceURL = conferenceURL
    }

    func status(at now: Date) -> CalendarEntryStatus {
        if start > now { return .upcoming }
        if end > now { return .inProgress }
        return .ended
    }

    /// Reminders are points in time; one counts as running for an hour after it is due.
    func isActive(at time: Date) -> Bool {
        if kind.isReminder {
            return start <= time && time < start.addingTimeInterval(3600)
        }
        return start <= time && end > time
    }

    /// A conference can be joined from 15 minutes before it starts.
    func isJoinable(at now: Date) -> Bool {
        start.addingTimeInterval(-15 * 60) <= now
    }

    /// Returns a copy with a reminder's completion flipped, for optimistic updates.
    func withReminderCompleted(_ completed: Bool) -> CalendarEntry {
        guard kind.isReminder else { return self }
        return CalendarEntry(
            itemIdentifier: itemIdentifier,
            start: start,
            end: end,
            title: title,
            location: location,
            notes: notes,
            url: url,
            isAllDay: isAllDay,
            kind: .reminder(completed: completed),
            calendar: calendar,
            hasRecurrenceRules: hasRecurrenceRules,
            priority: priority,
            conferenceURL: conferenceURL
        )
    }
}

// MARK: - Conference links

/// Video-call services recognised in an event's URL, location or notes, with their brand colours.
enum ConferenceProvider: String, CaseIterable, Sendable {
    case zoom, teams, meet, webex, facetime, goToMeeting, blueJeans, whereby, jitsi, discord, generic

    var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Teams"
        case .meet: "Meet"
        case .webex: "Webex"
        case .facetime: "FaceTime"
        case .goToMeeting: "GoToMeeting"
        case .blueJeans: "BlueJeans"
        case .whereby: "Whereby"
        case .jitsi: "Jitsi"
        case .discord: "Discord"
        case .generic: ""
        }
    }

    /// Brand colour; nil for unknown services, which use the system accent colour.
    var brandColor: CalendarColor? {
        switch self {
        case .zoom: CalendarColor(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: CalendarColor(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: CalendarColor(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: CalendarColor(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: CalendarColor(red: 0.2, green: 0.78, blue: 0.35)
        case .goToMeeting: CalendarColor(red: 0.95, green: 0.5, blue: 0.13)
        case .blueJeans: CalendarColor(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: CalendarColor(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: CalendarColor(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: CalendarColor(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: nil
        }
    }

    var tint: Color { brandColor?.color ?? Color.accentColor }

    /// Fragments of the host name that identify the service.
    var hostMarkers: [String] {
        switch self {
        case .zoom: ["zoom.us"]
        case .teams: ["teams.microsoft.com"]
        case .meet: ["meet.google.com"]
        case .webex: ["webex.com"]
        case .facetime: ["facetime.apple.com"]
        case .goToMeeting: ["gotomeeting.com"]
        case .blueJeans: ["bluejeans.com"]
        case .whereby: ["whereby.com"]
        case .jitsi: ["meet.jit.si", "jitsi"]
        case .discord: ["discord.gg", "discord.com"]
        case .generic: []
        }
    }

    /// The desktop app's URL scheme, tried before the web link when the app is installed.
    var nativeScheme: String? {
        switch self {
        case .teams: "msteams"
        case .facetime: "facetime"
        case .discord: "discord"
        // Zoom's web link already hands off to the app; rewriting it to zoommtg:// drops the
        // meeting parameters, so it is opened as is.
        default: nil
        }
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return .generic }
        return allCases.first { provider in
            provider.hostMarkers.contains { host.contains($0) }
        } ?? .generic
    }

    static func isConferenceURL(_ url: URL) -> Bool {
        detect(from: url) != .generic
    }

    /// The URL to open for `url`: the native-scheme variant when one exists, else the link.
    func launchURL(for url: URL) -> URL {
        guard let scheme = nativeScheme,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = scheme
        return components.url ?? url
    }

    /// The first conference link in free text such as a location or notes field.
    static func firstConferenceURL(in text: String) -> URL? {
        guard !text.isEmpty, let detector = linkDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, isConferenceURL(url) { return url }
        }
        return nil
    }

    /// Picks an event's conference link from its URL field, then its location, then its notes.
    static func conferenceURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isConferenceURL(url) { return url }
        if let location, let found = firstConferenceURL(in: location) { return found }
        if let notes, let found = firstConferenceURL(in: notes) { return found }
        return nil
    }

    /// `NSDataDetector` is immutable and Sendable, so one instance serves every fetch.
    private static let linkDetector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}

// MARK: - Opening items in other apps

enum ThirdPartyCalendarApp: String, CaseIterable, Identifiable, Sendable {
    case fantastical
    case notionCalendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fantastical: "Fantastical"
        case .notionCalendar: "Notion Calendar"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .fantastical: ["com.flexibits.fantastical2.mac", "com.flexibits.fantastical"]
        case .notionCalendar: ["com.cron.electron"]
        }
    }
}

enum FantasticalViewStyle: String, CaseIterable, Identifiable, Sendable {
    case mini
    case calendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mini: "Mini View"
        case .calendar: "Full Calendar"
        }
    }
}

/// Which app a click on an event opens.
enum CalendarOpener: Equatable, Sendable {
    case appleCalendar
    case fantastical(FantasticalViewStyle)
    case notionCalendar
}

/// Deep links into Calendar, Reminders, Fantastical and Notion Calendar.
enum CalendarAppLink {
    static func url(for entry: CalendarEntry, opener: CalendarOpener) -> URL? {
        // Reminders always open in Reminders.
        if entry.kind.isReminder { return reminderURL(for: entry) }
        switch opener {
        case .appleCalendar:
            return appleCalendarURL(for: entry)
        case .fantastical(let style):
            return URL(string: "x-fantastical3://show/\(style.rawValue)/\(dayString(entry.start))")
        case .notionCalendar:
            return notionCalendarURL(for: entry)
        }
    }

    static func reminderURL(for entry: CalendarEntry) -> URL? {
        guard let id = entry.itemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
    }

    /// `ical://ekevent[/<occurrence>]/<id>?method=show&options=more`; repeating events name the
    /// occurrence by its start, in UTC unless the event is all-day.
    static func appleCalendarURL(for entry: CalendarEntry) -> URL? {
        guard let id = entry.itemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        var occurrence = ""
        if entry.hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !entry.isAllDay { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
            occurrence = "/" + formatter.string(from: entry.start)
        }
        return URL(string: "ical://ekevent\(occurrence)/\(id)?method=show&options=more")
    }

    static func notionCalendarURL(for entry: CalendarEntry) -> URL? {
        let iso = ISO8601DateFormatter()
        var components = URLComponents()
        components.scheme = "cron"
        components.host = "showEvent"
        components.queryItems = [
            URLQueryItem(name: "accountEmail", value: entry.calendar.accountName),
            URLQueryItem(name: "iCalUID", value: entry.itemIdentifier),
            URLQueryItem(name: "startDate", value: iso.string(from: entry.start)),
            URLQueryItem(name: "endDate", value: iso.string(from: entry.end)),
            URLQueryItem(name: "title", value: entry.title)
        ]
        return components.url
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Filtering and auto-scroll

enum CalendarEventFilter {
    /// List filter: completed reminders go when hidden; all-day events go when hidden.
    /// Reminders are judged on completion only, so an all-day reminder stays visible.
    static func visibleEntries(
        _ entries: [CalendarEntry],
        hideCompletedReminders: Bool,
        hideAllDayEvents: Bool
    ) -> [CalendarEntry] {
        entries.filter { entry in
            if case .reminder(let completed) = entry.kind {
                return !completed || !hideCompletedReminders
            }
            return !(entry.isAllDay && hideAllDayEvents)
        }
    }

    /// All-day and timed entries, each in start order.
    static func split(_ entries: [CalendarEntry]) -> (allDay: [CalendarEntry], timed: [CalendarEntry]) {
        let sorted = entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset : lhs.element.start < rhs.element.start
            }
            .map(\.element)
        return (sorted.filter(\.isAllDay), sorted.filter { !$0.isAllDay })
    }

    /// The timed entry the list scrolls to: a running call with a join link, else whatever is
    /// running, else the next to start, else the last of the day.
    static func scrollTarget(in timed: [CalendarEntry], at reference: Date) -> CalendarEntry? {
        timed.first { $0.conferenceURL != nil && $0.isActive(at: reference) }
            ?? timed.first { $0.isActive(at: reference) }
            ?? timed.first { $0.start > reference }
            ?? timed.last
    }

    /// The moment auto-scroll measures against: now for today, midnight for any other day.
    static func scrollReference(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.isDate(day, inSameDayAs: now) ? now : calendar.startOfDay(for: day)
    }
}

// MARK: - Date strip and month grid

/// The horizontal date strip of the compact panel: a week back, two weeks ahead, two empty
/// cells at each end so the first and last days can reach the centre.
struct CalendarDayStrip: Equatable, Sendable {
    var daysBack = 7
    var daysAhead = 14
    var step = 1
    var edgeSpacers = 2

    var dayCount: Int {
        let span = Double(daysBack + daysAhead) / Double(max(step, 1))
        return Int(span.rounded(.up)) + 1
    }

    var itemCount: Int { dayCount + 2 * edgeSpacers }

    func isSpacer(_ index: Int) -> Bool {
        index < edgeSpacers || index >= edgeSpacers + dayCount
    }

    var dayIndices: Range<Int> { edgeSpacers..<(edgeSpacers + dayCount) }

    func firstDay(today: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -daysBack, to: start) ?? start
    }

    func day(at index: Int, today: Date, calendar: Calendar = .current) -> Date {
        let offset = (index - edgeSpacers) * max(step, 1)
        let first = firstDay(today: today, calendar: calendar)
        return calendar.date(byAdding: .day, value: offset, to: first) ?? first
    }

    /// The cell for `date`, clamped to the strip.
    func index(of date: Date, today: Date, calendar: Calendar = .current) -> Int {
        let first = firstDay(today: today, calendar: calendar)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: first, to: target).day ?? 0
        let position = min(max(days / max(step, 1), 0), dayCount - 1)
        return edgeSpacers + position
    }
}

enum CalendarMonthGrid {
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// Every day of the weeks that touch `month`'s month, so the grid starts and ends on whole
    /// weeks in the user's first weekday.
    static func days(for month: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else { return [] }

        var days: [Date] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// One-letter weekday headers starting at the calendar's first weekday.
    static func weekdayInitials(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return symbols }
        let first = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[first...] + symbols[..<first]).map { String($0.prefix(1)) }
    }
}

/// Fixed sizes of the calendar panels.
enum CalendarLayout {
    /// The compact panel beside the media player.
    static let compactHeight: CGFloat = 120
    /// Height of the all-day chip row.
    static let allDayChipRowHeight: CGFloat = 28
    /// Vertical padding of the chip row and of each chip.
    static let allDayVerticalPadding: CGFloat = 3
    /// Space the timed list leaves for the floating all-day strip (row + divider + margin).
    static let allDayListInset: CGFloat = 30
    static let dateStripHeight: CGFloat = 50
    static let dateStripFadeWidth: CGFloat = 16
    static let headerLabelWidth: CGFloat = 72
    /// Gap between the date strip and the event lines under it.
    static let compactSectionSpacing: CGFloat = 4
    static let compactRowSpacing: CGFloat = 3

    /// Standalone height: the open height less the header and 36 pt, at least 130.
    static func standaloneHeight(openHeight: CGFloat, closedHeight: CGFloat) -> CGFloat {
        max(130, openHeight - max(24, closedHeight) - 36)
    }
}

extension CalendarEventFilter {
    /// The days of `[firstDay, firstDay + dayCount)` that have at least one entry, keyed by
    /// midnight, each with the colour of its earliest entry. The compact date strip tints these
    /// days so they stand out without opening them. An entry counts on every day it overlaps;
    /// a reminder or zero-length event counts on the day it falls on.
    static func eventDays(
        _ entries: [CalendarEntry],
        from firstDay: Date,
        dayCount: Int,
        calendar: Calendar = .current
    ) -> [Date: CalendarColor] {
        let ordered = entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset : lhs.element.start < rhs.element.start
            }
            .map(\.element)
        var days: [Date: CalendarColor] = [:]
        var dayStart = calendar.startOfDay(for: firstDay)
        for _ in 0..<max(dayCount, 0) {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let first = ordered.first { entry in
                if entry.kind.isReminder || entry.end <= entry.start {
                    return entry.start >= dayStart && entry.start < dayEnd
                }
                return entry.start < dayEnd && entry.end > dayStart
            }
            if let first { days[dayStart] = first.calendar.color }
            dayStart = dayEnd
        }
        return days
    }
}
