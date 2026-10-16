import AppKit
import Combine
import EventKit
import SwiftUI

/// Calendar data for the notch: the selected day's events and reminders, the upcoming
/// entries that drive the reminder live activity, the calendar list and access state.
///
/// Fetch timing: a forced fetch whenever the day changes, a 15-s
/// dedupe for unforced fetches, EventKit change notifications throttled to one refresh per
/// 20 s and ignored for 6 s after a refresh, and a 60-s refresh loop.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    static let fetchDedupeInterval: TimeInterval = 15
    static let storeChangeThrottle: TimeInterval = 20
    static let selfChangeSuppression: TimeInterval = 6
    static let refreshLoopInterval: TimeInterval = 60
    /// How far ahead the reminder live activity looks.
    static let upcomingWindow: TimeInterval = 24 * 3600

    /// Midnight of the day shown in the panel.
    @Published private(set) var selectedDay: Date
    /// Everything on `selectedDay`, sorted by start.
    @Published private(set) var events: [CalendarEntry] = []
    /// Entries from today's midnight to a day from now, for the reminder live activity.
    @Published private(set) var upcomingEvents: [CalendarEntry] = []
    /// Days of the compact date strip that have something on them, keyed by midnight, with
    /// the colour of the day's first entry.
    @Published private(set) var eventDays: [Date: CalendarColor] = [:]
    @Published private(set) var calendars: [CalendarSource] = []
    @Published private(set) var eventAuthorization: EKAuthorizationStatus
    @Published private(set) var reminderAuthorization: EKAuthorizationStatus
    @Published private(set) var isRequestingAccess = false
    /// True while the pointer is over the calendar, so a scroll there does not count as a
    /// close swipe.
    @Published var isHoveringCalendar = false

    let settings: CalendarSettings
    private let service: CalendarEventService

    private var isRunning = false
    private var lastDayFetch: Date?
    private var lastUpcomingFetch: Date?
    private var lastStripFetch: Date?
    private var stripEntries: [CalendarEntry] = []
    private let strip = CalendarDayStrip()
    private var dayFetchGeneration = 0
    private var upcomingFetchGeneration = 0
    private var stripFetchGeneration = 0
    private var nextAllowedStoreRefresh = Date.distantPast
    private var ignoreStoreChangesUntil = Date.distantPast
    private var pendingStoreRefresh: Task<Void, Never>?
    private var refreshLoop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    init(settings: CalendarSettings = .shared, service: CalendarEventService = CalendarEventService()) {
        self.settings = settings
        self.service = service
        selectedDay = Calendar.current.startOfDay(for: Date())
        eventAuthorization = CalendarEventService.status(for: .event)
        reminderAuthorization = CalendarEventService.status(for: .reminder)
    }

    // MARK: - Access

    var hasEventAccess: Bool { CalendarEventService.isGranted(eventAuthorization) }
    var hasReminderAccess: Bool { CalendarEventService.isGranted(reminderAuthorization) }
    var hasAnyAccess: Bool { hasEventAccess || hasReminderAccess }
    /// At least one of events or reminders can still show the system prompt.
    var canRequestAccess: Bool {
        eventAuthorization == .notDetermined || reminderAuthorization == .notDetermined
    }

    var eventCalendars: [CalendarSource] { calendars.filter { !$0.isReminderList } }
    var reminderLists: [CalendarSource] { calendars.filter(\.isReminderList) }

    /// Re-reads the authorization status (access may have changed in System Settings) and
    /// reloads when it did.
    func refreshAuthorizationStatus() {
        let event = CalendarEventService.status(for: .event)
        let reminder = CalendarEventService.status(for: .reminder)
        let changed = event != eventAuthorization || reminder != reminderAuthorization
        if event != eventAuthorization { eventAuthorization = event }
        if reminder != reminderAuthorization { reminderAuthorization = reminder }
        if changed {
            Task { await reloadAll(force: true) }
        }
    }

    /// Asks for full access to events, then reminders, where the user has not decided yet.
    func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        if eventAuthorization == .notDetermined {
            _ = await service.requestFullAccess(to: .event)
        }
        if CalendarEventService.status(for: .reminder) == .notDetermined {
            _ = await service.requestFullAccess(to: .reminder)
        }
        eventAuthorization = CalendarEventService.status(for: .event)
        reminderAuthorization = CalendarEventService.status(for: .reminder)
        await reloadAll(force: true)
    }

    func openPrivacySettings() {
        let pane = hasEventAccess && !hasReminderAccess ? "Privacy_Reminders" : "Privacy_Calendars"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshAuthorizationStatus()
        observeStoreChanges()
        observeSettings()
        startRefreshLoop()
        Task { await reloadAll(force: true) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        cancellables.removeAll()
        pendingStoreRefresh?.cancel()
        pendingStoreRefresh = nil
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    // MARK: - Fetching

    /// Shows `day` and fetches it (always forced).
    func select(day: Date) {
        let normalized = Calendar.current.startOfDay(for: day)
        if normalized != selectedDay { selectedDay = normalized }
        Task { await refreshSelectedDay(force: true) }
    }

    /// Back to today, done whenever the notch opens or closes.
    func resetToToday() {
        select(day: Date())
    }

    func reloadAll(force: Bool) async {
        await reloadCalendars()
        await refreshSelectedDay(force: force)
        await refreshUpcoming(force: force)
        await refreshEventDays(force: force)
    }

    func reloadCalendars() async {
        guard hasAnyAccess else {
            if !calendars.isEmpty { calendars = [] }
            return
        }
        let loaded = await service.calendars()
        if loaded != calendars { calendars = loaded }
    }

    func refreshSelectedDay(force: Bool) async {
        guard hasAnyAccess else {
            if !events.isEmpty { events = [] }
            return
        }
        if !force, let lastDayFetch, Date().timeIntervalSince(lastDayFetch) < Self.fetchDedupeInterval { return }
        dayFetchGeneration &+= 1
        let generation = dayFetchGeneration
        let start = selectedDay
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let fetched = await service.entries(
            from: start,
            to: end,
            calendarIDs: selectionFilter,
            includeCompletedReminders: !settings.hideCompletedReminders
        )
        guard generation == dayFetchGeneration else { return }
        if fetched != events { events = fetched }
        lastDayFetch = Date()
    }

    func refreshUpcoming(force: Bool) async {
        guard hasAnyAccess, settings.enableReminderLiveActivity else {
            if !upcomingEvents.isEmpty { upcomingEvents = [] }
            return
        }
        let now = Date()
        if !force, let lastUpcomingFetch, now.timeIntervalSince(lastUpcomingFetch) < Self.fetchDedupeInterval { return }
        upcomingFetchGeneration &+= 1
        let generation = upcomingFetchGeneration
        let start = Calendar.current.startOfDay(for: now)
        let end = now.addingTimeInterval(Self.upcomingWindow)
        let fetched = await service.entries(
            from: start,
            to: end,
            calendarIDs: selectionFilter,
            includeCompletedReminders: !settings.hideCompletedReminders
        )
        guard generation == upcomingFetchGeneration else { return }
        if fetched != upcomingEvents { upcomingEvents = fetched }
        lastUpcomingFetch = Date()
    }

    /// Fetches everything across the date strip (a week back, two weeks ahead) so the strip
    /// can tint the days that have events.
    func refreshEventDays(force: Bool) async {
        guard hasAnyAccess else {
            stripEntries = []
            if !eventDays.isEmpty { eventDays = [:] }
            return
        }
        if !force, let lastStripFetch, Date().timeIntervalSince(lastStripFetch) < Self.fetchDedupeInterval { return }
        stripFetchGeneration &+= 1
        let generation = stripFetchGeneration
        let start = strip.firstDay(today: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: strip.dayCount, to: start) else { return }
        let fetched = await service.entries(
            from: start,
            to: end,
            calendarIDs: selectionFilter,
            includeCompletedReminders: !settings.hideCompletedReminders
        )
        guard generation == stripFetchGeneration else { return }
        stripEntries = fetched
        lastStripFetch = Date()
        updateEventDays()
    }

    /// Applies the hide settings, so a hidden all-day event or completed reminder never tints
    /// a day.
    private func updateEventDays() {
        let visible = CalendarEventFilter.visibleEntries(
            stripEntries,
            hideCompletedReminders: settings.hideCompletedReminders,
            hideAllDayEvents: settings.hideAllDayEvents
        )
        let days = CalendarEventFilter.eventDays(
            visible,
            from: strip.firstDay(today: Date()),
            dayCount: strip.dayCount
        )
        if days != eventDays { eventDays = days }
    }

    /// nil fetches every calendar.
    private var selectionFilter: Set<String>? {
        switch settings.calendarSelection {
        case .all: nil
        case .selected(let ids): ids
        }
    }

    // MARK: - Calendar selection

    func isSelected(_ calendar: CalendarSource) -> Bool {
        switch settings.calendarSelection {
        case .all: true
        case .selected(let ids): ids.contains(calendar.id)
        }
    }

    func setSelected(_ calendars: [CalendarSource], isSelected: Bool) {
        settings.calendarSelection = CalendarSettings.updatedSelection(
            settings.calendarSelection,
            setting: Set(calendars.map(\.id)),
            selected: isSelected,
            allIDs: Set(self.calendars.map(\.id))
        )
        Task {
            await refreshSelectedDay(force: true)
            await refreshUpcoming(force: true)
            await refreshEventDays(force: true)
        }
    }

    // MARK: - Actions

    /// Ticks or unticks a reminder, updating the list at once and refetching after the save.
    func setReminderCompleted(_ entry: CalendarEntry, completed: Bool) {
        guard entry.kind.isReminder else { return }
        events = events.map { $0.itemIdentifier == entry.itemIdentifier ? $0.withReminderCompleted(completed) : $0 }
        Task {
            _ = await service.setReminderCompleted(itemIdentifier: entry.itemIdentifier, completed: completed)
            await refreshSelectedDay(force: true)
            await refreshUpcoming(force: true)
        }
    }

    /// Opens the entry in Calendar, Reminders, Fantastical or Notion Calendar.
    func open(_ entry: CalendarEntry) {
        if let url = CalendarAppLink.url(for: entry, opener: settings.opener) {
            NSWorkspace.shared.open(url)
        } else if settings.opener == .notionCalendar {
            launchApp(bundleIdentifiers: ThirdPartyCalendarApp.notionCalendar.bundleIdentifiers)
        }
    }

    /// Opens a conference link, in the provider's app when it is installed.
    func joinConference(_ url: URL) {
        let native = ConferenceProvider.detect(from: url).launchURL(for: url)
        if native != url, NSWorkspace.shared.urlForApplication(toOpen: native) != nil {
            NSWorkspace.shared.open(native)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func launchApp(bundleIdentifiers: [String]) {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
                return
            }
        }
    }

    // MARK: - Observation

    private func observeStoreChanges() {
        observers.append(
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.handleStoreChanged() }
            }
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshAuthorizationStatus()
                    Task { await self.reloadAll(force: true) }
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task {
                        await self.refreshUpcoming(force: true)
                        await self.refreshEventDays(force: true)
                    }
                }
            }
        )
    }

    private func observeSettings() {
        // Completed reminders are fetched only when shown, so this toggle needs a refetch.
        settings.$hideCompletedReminders
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.refreshSelectedDay(force: true)
                    await self.refreshUpcoming(force: true)
                    await self.refreshEventDays(force: true)
                }
            }
            .store(in: &cancellables)
        settings.$hideAllDayEvents
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateEventDays() }
            .store(in: &cancellables)
        settings.$enableReminderLiveActivity
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshUpcoming(force: true) }
            }
            .store(in: &cancellables)
    }

    private func handleStoreChanged() {
        let now = Date()
        guard now >= ignoreStoreChangesUntil else { return }
        if now < nextAllowedStoreRefresh {
            scheduleStoreRefresh(after: max(nextAllowedStoreRefresh.timeIntervalSince(now), 0.05))
            return
        }
        nextAllowedStoreRefresh = now.addingTimeInterval(Self.storeChangeThrottle)
        scheduleStoreRefresh(after: 0)
    }

    private func scheduleStoreRefresh(after delay: TimeInterval) {
        pendingStoreRefresh?.cancel()
        pendingStoreRefresh = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            await self?.performStoreRefresh()
        }
    }

    private func performStoreRefresh() async {
        pendingStoreRefresh = nil
        await reloadCalendars()
        await refreshSelectedDay(force: true)
        await refreshUpcoming(force: true)
        await refreshEventDays(force: true)
        nextAllowedStoreRefresh = Date().addingTimeInterval(Self.storeChangeThrottle)
        ignoreStoreChangesUntil = Date().addingTimeInterval(Self.selfChangeSuppression)
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshLoopInterval))
                guard !Task.isCancelled, let self else { return }
                guard self.hasAnyAccess else { continue }
                await self.refreshUpcoming(force: false)
                await self.refreshEventDays(force: false)
            }
        }
    }
}
