import Combine
import Foundation

/// How the reminder live activity draws its countdown on the closed notch.
enum ReminderCountdownStyle: String, CaseIterable, Identifiable, Sendable {
    case ring = "Ring"
    case digital = "Digital"
    case minutes = "Minutes"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Which calendars and reminder lists feed the notch.
enum CalendarSelection: Equatable, Sendable {
    case all
    case selected(Set<String>)
}

/// Calendar preferences, stored under "calendar." keys with Atoll's defaults.
@MainActor
final class CalendarSettings: ObservableObject {
    static let shared = CalendarSettings()

    enum Key {
        static let showCalendar = "calendar.showCalendar"
        static let hideCompletedReminders = "calendar.hideCompletedReminders"
        static let hideAllDayEvents = "calendar.hideAllDayEvents"
        static let showFullEventTitles = "calendar.showFullEventTitles"
        static let autoScrollToNextEvent = "calendar.autoScrollToNextEvent"
        static let selectionMode = "calendar.selectionMode"
        static let selectedCalendarIDs = "calendar.selectedCalendarIDs"
        static let enableReminderLiveActivity = "calendar.enableReminderLiveActivity"
        static let reminderPresentationStyle = "calendar.reminderPresentationStyle"
        static let reminderLeadTime = "calendar.reminderLeadTime"
        static let reminderSneakPeekDuration = "calendar.reminderSneakPeekDuration"
        static let enableThirdPartyCalendarApp = "calendar.enableThirdPartyCalendarApp"
        static let selectedCalendarApp = "calendar.selectedCalendarApp"
        static let fantasticalDefaultView = "calendar.fantasticalDefaultView"
    }

    /// "Notify before", in minutes.
    static let leadTimeRange = 1...60
    /// "Sneak peek duration", in seconds.
    static let sneakPeekDurationRange: ClosedRange<Double> = 3...20

    private let defaults: UserDefaults

    /// Show the calendar on the Home tab.
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: Key.showCalendar) } }
    @Published var hideCompletedReminders: Bool {
        didSet { defaults.set(hideCompletedReminders, forKey: Key.hideCompletedReminders) }
    }
    @Published var hideAllDayEvents: Bool {
        didSet { defaults.set(hideAllDayEvents, forKey: Key.hideAllDayEvents) }
    }
    @Published var showFullEventTitles: Bool {
        didSet { defaults.set(showFullEventTitles, forKey: Key.showFullEventTitles) }
    }
    @Published var autoScrollToNextEvent: Bool {
        didSet { defaults.set(autoScrollToNextEvent, forKey: Key.autoScrollToNextEvent) }
    }
    @Published var calendarSelection: CalendarSelection {
        didSet { Self.store(selection: calendarSelection, in: defaults) }
    }
    @Published var enableReminderLiveActivity: Bool {
        didSet { defaults.set(enableReminderLiveActivity, forKey: Key.enableReminderLiveActivity) }
    }
    @Published var reminderPresentationStyle: ReminderCountdownStyle {
        didSet { defaults.set(reminderPresentationStyle.rawValue, forKey: Key.reminderPresentationStyle) }
    }
    /// Minutes before an event that the reminder live activity appears.
    @Published var reminderLeadTime: Int {
        didSet {
            let clamped = min(max(reminderLeadTime, Self.leadTimeRange.lowerBound), Self.leadTimeRange.upperBound)
            if clamped != reminderLeadTime {
                reminderLeadTime = clamped
            }
            defaults.set(reminderLeadTime, forKey: Key.reminderLeadTime)
        }
    }
    /// Seconds the reminder sneak peek stays up; also the "about to start" window that turns
    /// the activity red.
    @Published var reminderSneakPeekDuration: Double {
        didSet {
            let range = Self.sneakPeekDurationRange
            let clamped = min(max(reminderSneakPeekDuration, range.lowerBound), range.upperBound)
            if clamped != reminderSneakPeekDuration {
                reminderSneakPeekDuration = clamped
            }
            defaults.set(reminderSneakPeekDuration, forKey: Key.reminderSneakPeekDuration)
        }
    }
    @Published var enableThirdPartyCalendarApp: Bool {
        didSet { defaults.set(enableThirdPartyCalendarApp, forKey: Key.enableThirdPartyCalendarApp) }
    }
    @Published var selectedCalendarApp: ThirdPartyCalendarApp {
        didSet { defaults.set(selectedCalendarApp.rawValue, forKey: Key.selectedCalendarApp) }
    }
    @Published var fantasticalDefaultView: FantasticalViewStyle {
        didSet { defaults.set(fantasticalDefaultView.rawValue, forKey: Key.fantasticalDefaultView) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCalendar = defaults.object(forKey: Key.showCalendar) as? Bool ?? true
        hideCompletedReminders = defaults.object(forKey: Key.hideCompletedReminders) as? Bool ?? true
        hideAllDayEvents = defaults.object(forKey: Key.hideAllDayEvents) as? Bool ?? false
        showFullEventTitles = defaults.object(forKey: Key.showFullEventTitles) as? Bool ?? false
        autoScrollToNextEvent = defaults.object(forKey: Key.autoScrollToNextEvent) as? Bool ?? true
        calendarSelection = Self.loadSelection(from: defaults)
        enableReminderLiveActivity = defaults.object(forKey: Key.enableReminderLiveActivity) as? Bool ?? true
        reminderPresentationStyle = ReminderCountdownStyle(
            rawValue: defaults.string(forKey: Key.reminderPresentationStyle) ?? ""
        ) ?? .ring
        let lead = defaults.object(forKey: Key.reminderLeadTime) as? Int ?? 5
        reminderLeadTime = min(max(lead, Self.leadTimeRange.lowerBound), Self.leadTimeRange.upperBound)
        let peek = defaults.object(forKey: Key.reminderSneakPeekDuration) as? Double ?? 5
        reminderSneakPeekDuration = min(
            max(peek, Self.sneakPeekDurationRange.lowerBound),
            Self.sneakPeekDurationRange.upperBound
        )
        enableThirdPartyCalendarApp = defaults.object(forKey: Key.enableThirdPartyCalendarApp) as? Bool ?? false
        selectedCalendarApp = ThirdPartyCalendarApp(
            rawValue: defaults.string(forKey: Key.selectedCalendarApp) ?? ""
        ) ?? .fantastical
        fantasticalDefaultView = FantasticalViewStyle(
            rawValue: defaults.string(forKey: Key.fantasticalDefaultView) ?? ""
        ) ?? .mini
    }

    /// The app that opens when an event is clicked.
    var opener: CalendarOpener {
        guard enableThirdPartyCalendarApp else { return .appleCalendar }
        switch selectedCalendarApp {
        case .fantastical: return .fantastical(fantasticalDefaultView)
        case .notionCalendar: return .notionCalendar
        }
    }

    /// Lead time in seconds; never below a minute.
    var reminderLeadInterval: TimeInterval { TimeInterval(max(1, reminderLeadTime) * 60) }

    // MARK: - Selection

    /// Atoll's selection rules: unticking from "all" switches to an explicit list; an empty
    /// list or one naming every calendar collapses back to "all".
    static func updatedSelection(
        _ current: CalendarSelection,
        setting ids: Set<String>,
        selected: Bool,
        allIDs: Set<String>
    ) -> CalendarSelection {
        switch current {
        case .all:
            guard !selected else { return .all }
            let remaining = allIDs.subtracting(ids)
            return remaining.isEmpty ? .all : .selected(remaining)
        case .selected(var identifiers):
            if selected {
                identifiers.formUnion(ids)
            } else {
                identifiers.subtract(ids)
            }
            if identifiers.isEmpty || (!allIDs.isEmpty && identifiers.isSuperset(of: allIDs)) {
                return .all
            }
            return .selected(identifiers)
        }
    }

    static func loadSelection(from defaults: UserDefaults) -> CalendarSelection {
        guard defaults.string(forKey: Key.selectionMode) == "selected" else { return .all }
        let ids = defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? []
        return ids.isEmpty ? .all : .selected(Set(ids))
    }

    static func store(selection: CalendarSelection, in defaults: UserDefaults) {
        switch selection {
        case .all:
            defaults.set("all", forKey: Key.selectionMode)
            defaults.removeObject(forKey: Key.selectedCalendarIDs)
        case .selected(let ids):
            defaults.set("selected", forKey: Key.selectionMode)
            defaults.set(ids.sorted(), forKey: Key.selectedCalendarIDs)
        }
    }
}
