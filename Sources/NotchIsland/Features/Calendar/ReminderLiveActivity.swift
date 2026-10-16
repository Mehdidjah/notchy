import AppKit
import Combine
import SwiftUI

/// An upcoming event or reminder and the moment its live activity begins.
struct ReminderEntry: Identifiable, Hashable, Sendable {
    let event: CalendarEntry
    let triggerDate: Date
    let leadTime: TimeInterval

    var id: String { event.id }
}

/// Scheduling rules and countdown text of the reminder live activity.
enum ReminderSchedule {
    static let standardSymbol = "calendar.badge.clock"
    static let criticalSymbol = "calendar.badge.exclamationmark"

    /// One entry per future item, triggered `leadMinutes` before it starts, earliest first.
    /// All-day items and completed reminders are skipped when the list hides them.
    static func entries(
        from events: [CalendarEntry],
        leadMinutes: Int,
        now: Date,
        hideAllDayEvents: Bool,
        hideCompletedReminders: Bool
    ) -> [ReminderEntry] {
        let lead = TimeInterval(max(1, leadMinutes) * 60)
        var seen = Set<String>()
        return events
            .filter { event in
                if hideAllDayEvents && event.isAllDay { return false }
                if hideCompletedReminders && event.kind.isCompletedReminder { return false }
                return event.start > now
            }
            .filter { seen.insert($0.id).inserted }
            .map { ReminderEntry(event: $0, triggerDate: $0.start.addingTimeInterval(-lead), leadTime: lead) }
            .sorted { $0.triggerDate < $1.triggerDate }
    }

    static func remaining(_ entry: ReminderEntry, now: Date) -> TimeInterval {
        max(entry.event.start.timeIntervalSince(now), 0)
    }

    /// Share of the lead time already elapsed, 0...1.
    static func progress(_ entry: ReminderEntry, now: Date) -> Double {
        guard entry.leadTime > 0 else { return 1 }
        let elapsed = entry.leadTime - remaining(entry, now: now)
        return min(max(elapsed / entry.leadTime, 0), 1)
    }

    /// "MM:SS" until the start.
    static func digitalText(_ entry: ReminderEntry, now: Date) -> String {
        let seconds = Int(remaining(entry, now: now).rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// "in N min", rounded up and never below one minute.
    static func minutesText(_ entry: ReminderEntry, now: Date) -> String {
        let minutes = max(1, Int((remaining(entry, now: now) / 60).rounded(.up)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    /// The last `window` seconds before the start, when the activity turns red.
    static func isCritical(_ entry: ReminderEntry, now: Date, window: TimeInterval) -> Bool {
        guard window > 0 else { return false }
        let left = entry.event.start.timeIntervalSince(now)
        return left > 0 && left <= window
    }

    /// Calendar colour lifted (or toned) to 0.7 luminance; red when critical.
    static func accentColor(_ entry: ReminderEntry, critical: Bool) -> Color {
        critical ? .red : entry.event.calendar.color.adjustedToLuminance(0.7).color
    }

    /// The sneak-peek line: "Title • in 5 min • 10:30", or "Title • now" in the last seconds.
    static func sneakPeekText(_ entry: ReminderEntry, now: Date, window: TimeInterval) -> String {
        let title = entry.event.title.isEmpty ? "Upcoming Reminder" : entry.event.title
        let left = remaining(entry, now: now)
        if window > 0 && left <= window { return "\(title) • now" }
        let time = entry.event.start.formatted(date: .omitted, time: .shortened)
        let minutes = Int((left / 60).rounded(.up))
        switch minutes {
        case ...0: return "\(title) • now • \(time)"
        case 1: return "\(title) • in 1 min • \(time)"
        default: return "\(title) • in \(minutes) min • \(time)"
        }
    }
}

/// Sizes of the reminder wings, from Atoll's ReminderLiveActivity. Widths depend on the
/// closed notch height only, so the activity does not swell on hover.
enum ReminderWingMetrics {
    static let wingPadding: CGFloat = 16
    static let ringStrokeWidth: CGFloat = 3
    static let digitalFontSize: CGFloat = 16
    static let minutesFontSize: CGFloat = 13

    static func iconDiameter(closedHeight: CGFloat) -> CGFloat { max(closedHeight - 8, 26) }
    static func ringDiameter(closedHeight: CGFloat) -> CGFloat { max(min(closedHeight - 12, 22), 16) }
    static func leftWidth(closedHeight: CGFloat) -> CGFloat { wingPadding + iconDiameter(closedHeight: closedHeight) }

    static func digitalWidth(for text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: digitalFontSize, weight: .semibold)
        return max(measure(text, font: font) + 18, 76)
    }

    static func minutesWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: minutesFontSize, weight: .semibold)
        return max(measure(text, font: font) + 18, 88)
    }

    static func rightWidth(style: ReminderCountdownStyle, closedHeight: CGFloat, entry: ReminderEntry?, now: Date) -> CGFloat {
        switch style {
        case .ring:
            return wingPadding + ringDiameter(closedHeight: closedHeight)
        case .digital:
            let text = entry.map { ReminderSchedule.digitalText($0, now: now) } ?? "00:00"
            return wingPadding + digitalWidth(for: text)
        case .minutes:
            let text = entry.map { ReminderSchedule.minutesText($0, now: now) } ?? "in 1 min"
            return wingPadding + minutesWidth(for: text)
        }
    }

    static func measure(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }
}

/// The reminder live activity: from `reminderLeadTime` minutes before the next event or
/// reminder, the closed notch shows a calendar glyph in the calendar's colour on the left
/// and a countdown on the right. A sneak peek announces it, and a red one marks the final
/// seconds; at the start time it moves on to the next entry.
@MainActor
final class ReminderLiveActivityModel: ObservableObject, ClosedLiveActivity {
    static let shared = ReminderLiveActivityModel()

    static let eventsDebounce: Duration = .milliseconds(350)
    static let settingsDebounce: Duration = .milliseconds(200)

    let activityID = "calendar.reminder"
    let priority = ClosedActivityPriority.reminder

    /// The entry on the closed notch, if its lead window has begun.
    @Published private(set) var activeReminder: ReminderEntry?
    /// Advances every second while a reminder is active.
    @Published private(set) var now: Date
    @Published private(set) var upcomingEntries: [ReminderEntry] = []

    let settings: CalendarSettings
    private let eventsSource: AnyPublisher<[CalendarEntry], Never>?
    private let clock: () -> Date
    private let sneakPeekHandler: (SneakPeek) -> Void
    private let usesTimers: Bool

    private var latestEvents: [CalendarEntry] = []
    private var nextEntry: ReminderEntry?
    private var criticalPeekShown = false
    private var ticker: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var eventsDebounceTask: Task<Void, Never>?
    private var settingsDebounceTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?
    private let changes = PassthroughSubject<Void, Never>()
    private var lastLayoutKey: LayoutKey?
    private var isRunning = false

    private struct LayoutKey: Equatable {
        var visible: Bool
        var style: ReminderCountdownStyle
        var countdownText: String
    }

    /// - Parameters:
    ///   - events: upcoming entries; defaults to `CalendarStore.shared.$upcomingEvents`.
    ///   - clock: the current time, injectable for tests.
    ///   - sneakPeek: where sneak peeks go; defaults to the island's activity centre.
    ///   - usesTimers: false in tests, which drive `evaluate(at:)` by hand.
    init(
        settings: CalendarSettings = .shared,
        events: AnyPublisher<[CalendarEntry], Never>? = nil,
        clock: @escaping () -> Date = Date.init,
        sneakPeek: ((SneakPeek) -> Void)? = nil,
        usesTimers: Bool = true
    ) {
        self.settings = settings
        self.eventsSource = events
        self.clock = clock
        self.sneakPeekHandler = sneakPeek ?? { IslandActivityCenter.shared.requestSneakPeek($0) }
        self.usesTimers = usesTimers
        self.now = clock()
    }

    // MARK: - ClosedLiveActivity

    var isActivityVisible: Bool { settings.enableReminderLiveActivity && activeReminder != nil }

    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        ReminderWingMetrics.leftWidth(closedHeight: context.closedHeight)
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        ReminderWingMetrics.rightWidth(
            style: settings.reminderPresentationStyle,
            closedHeight: context.closedHeight,
            entry: activeReminder,
            now: now
        )
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ReminderLeftWingView(model: self, closedHeight: context.closedHeight))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(ReminderRightWingView(model: self, settings: settings, closedHeight: context.closedHeight))
    }

    // MARK: - Presentation helpers

    var criticalWindow: TimeInterval { settings.reminderSneakPeekDuration }

    func isCritical(_ entry: ReminderEntry) -> Bool {
        ReminderSchedule.isCritical(entry, now: now, window: criticalWindow)
    }

    func accent(for entry: ReminderEntry) -> Color {
        ReminderSchedule.accentColor(entry, critical: isCritical(entry))
    }

    /// Entries whose lead window is open right now (Atoll lists these in minimalistic mode).
    var activeWindowEntries: [ReminderEntry] {
        upcomingEntries.filter { $0.triggerDate <= now && $0.event.start >= now }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let source = eventsSource ?? CalendarStore.shared.$upcomingEvents.eraseToAnyPublisher()
        source
            .removeDuplicates()
            .sink { [weak self] events in self?.receive(events: events) }
            .store(in: &cancellables)

        settings.$enableReminderLiveActivity
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.scheduleSettingsRecalculation()
                } else {
                    self.deactivate()
                }
            }
            .store(in: &cancellables)

        Publishers.Merge3(
            settings.$reminderLeadTime.dropFirst().removeDuplicates().map { _ in () },
            settings.$hideAllDayEvents.dropFirst().removeDuplicates().map { _ in () },
            settings.$hideCompletedReminders.dropFirst().removeDuplicates().map { _ in () }
        )
        .sink { [weak self] in self?.scheduleSettingsRecalculation() }
        .store(in: &cancellables)

        // Style and window changes resize or recolour the wings; publish once the new value is set.
        Publishers.Merge(
            settings.$reminderPresentationStyle.dropFirst().map { _ in () },
            settings.$reminderSneakPeekDuration.dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.publishLayoutIfNeeded(force: true)
        }
        .store(in: &cancellables)

        if usesTimers {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.evaluate(at: self.clock())
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancellables.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        eventsDebounceTask?.cancel()
        settingsDebounceTask?.cancel()
        deactivate()
    }

    // MARK: - Inputs

    private func receive(events: [CalendarEntry]) {
        guard usesTimers else {
            apply(events: events)
            return
        }
        eventsDebounceTask?.cancel()
        eventsDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.eventsDebounce)
            guard !Task.isCancelled, let self else { return }
            self.apply(events: events)
        }
    }

    /// Takes a new event list (debounced in the app) and rebuilds the schedule.
    func apply(events: [CalendarEntry]) {
        guard events != latestEvents || upcomingEntries.isEmpty else { return }
        latestEvents = events
        recalculate(at: clock())
    }

    private func scheduleSettingsRecalculation() {
        guard usesTimers else {
            recalculate(at: clock())
            return
        }
        settingsDebounceTask?.cancel()
        settingsDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settingsDebounce)
            guard !Task.isCancelled, let self else { return }
            self.recalculate(at: self.clock())
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the upcoming list from the latest events and selects the first entry.
    func recalculate(at date: Date) {
        guard settings.enableReminderLiveActivity else {
            deactivate()
            return
        }
        upcomingEntries = ReminderSchedule.entries(
            from: latestEvents,
            leadMinutes: settings.reminderLeadTime,
            now: date,
            hideAllDayEvents: settings.hideAllDayEvents,
            hideCompletedReminders: settings.hideCompletedReminders
        )
        select(upcomingEntries.first, at: date)
    }

    private func select(_ entry: ReminderEntry?, at date: Date) {
        if entry != nextEntry {
            nextEntry = entry
            criticalPeekShown = false
        }
        evaluate(at: date)
    }

    /// Brings the activity up to date with `date`: drops an entry that has started and moves to
    /// the next, shows the active one and its sneak peeks, or waits for the next trigger.
    func evaluate(at date: Date) {
        guard settings.enableReminderLiveActivity else {
            deactivate()
            return
        }
        now = date

        guard let entry = nextEntry else {
            setActive(nil)
            stopTicker()
            criticalPeekShown = false
            return
        }

        if entry.event.start <= date {
            setActive(nil)
            stopTicker()
            evaluationTask?.cancel()
            criticalPeekShown = false
            upcomingEntries.removeAll { $0.event.start <= date }
            nextEntry = nil
            if let following = upcomingEntries.first {
                select(following, at: date)
            } else {
                publishLayoutIfNeeded()
            }
            return
        }

        if entry.triggerDate <= date {
            if activeReminder != entry {
                setActive(entry)
                criticalPeekShown = false
                sneakPeekHandler(sneakPeek(for: entry, at: date, critical: false, duration: criticalWindow))
            }
            let window = criticalWindow
            let left = entry.event.start.timeIntervalSince(date)
            if window > 0 && left > 0 {
                if left <= window {
                    if !criticalPeekShown {
                        let duration = min(window, max(left - 2, 0))
                        if duration > 0 {
                            sneakPeekHandler(sneakPeek(for: entry, at: date, critical: true, duration: duration))
                            criticalPeekShown = true
                        }
                    }
                } else {
                    criticalPeekShown = false
                }
            }
            startTickerIfNeeded()
        } else {
            setActive(nil)
            stopTicker()
            criticalPeekShown = false
            scheduleEvaluation(at: entry.triggerDate)
        }
        publishLayoutIfNeeded()
    }

    private func sneakPeek(for entry: ReminderEntry, at date: Date, critical: Bool, duration: TimeInterval) -> SneakPeek {
        SneakPeek(
            kind: .reminder,
            systemImage: critical ? ReminderSchedule.criticalSymbol : ReminderSchedule.standardSymbol,
            title: ReminderSchedule.sneakPeekText(entry, now: date, window: criticalWindow),
            subtitle: nil,
            level: nil,
            tint: ReminderSchedule.accentColor(entry, critical: critical),
            duration: .milliseconds(Int64((max(duration, 0.5) * 1000).rounded()))
        )
    }

    private func setActive(_ entry: ReminderEntry?) {
        guard activeReminder != entry else { return }
        activeReminder = entry
        publishLayoutIfNeeded()
    }

    private func deactivate() {
        nextEntry = nil
        upcomingEntries = []
        criticalPeekShown = false
        stopTicker()
        evaluationTask?.cancel()
        evaluationTask = nil
        setActive(nil)
        publishLayoutIfNeeded()
    }

    private func scheduleEvaluation(at date: Date) {
        evaluationTask?.cancel()
        guard usesTimers else { return }
        let delay = max(date.timeIntervalSince(clock()), 0)
        evaluationTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.evaluate(at: self.clock())
        }
    }

    private func startTickerIfNeeded() {
        guard usesTimers, ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.evaluate(at: self.clock())
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Tells the island to re-read visibility and wing widths when either may have changed.
    private func publishLayoutIfNeeded(force: Bool = false) {
        let style = settings.reminderPresentationStyle
        let countdown: String = switch style {
        case .ring: ""
        case .digital: activeReminder.map { ReminderSchedule.digitalText($0, now: now).count.description } ?? ""
        case .minutes: activeReminder.map { ReminderSchedule.minutesText($0, now: now) } ?? ""
        }
        let key = LayoutKey(visible: isActivityVisible, style: style, countdownText: countdown)
        guard force || key != lastLayoutKey else { return }
        lastLayoutKey = key
        changes.send()
    }
}

// MARK: - Wings

/// Calendar glyph tinted with the calendar's colour (red in the final seconds).
struct ReminderLeftWingView: View {
    @ObservedObject var model: ReminderLiveActivityModel
    let closedHeight: CGFloat

    var body: some View {
        if let entry = model.activeReminder {
            let critical = model.isCritical(entry)
            Image(systemName: critical ? ReminderSchedule.criticalSymbol : ReminderSchedule.standardSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ReminderSchedule.accentColor(entry, critical: critical))
                .frame(width: ReminderWingMetrics.iconDiameter(closedHeight: closedHeight))
                .frame(maxHeight: .infinity)
                .padding(.leading, ReminderWingMetrics.wingPadding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Upcoming: \(entry.event.title)")
        }
    }
}

/// Ring, "MM:SS" or "in N min" countdown, right-aligned.
struct ReminderRightWingView: View {
    @ObservedObject var model: ReminderLiveActivityModel
    @ObservedObject var settings: CalendarSettings
    let closedHeight: CGFloat

    var body: some View {
        if let entry = model.activeReminder {
            let accent = model.accent(for: entry)
            ReminderCountdownView(
                entry: entry,
                now: model.now,
                style: settings.reminderPresentationStyle,
                accent: accent,
                ringDiameter: ReminderWingMetrics.ringDiameter(closedHeight: closedHeight),
                digitalFontSize: ReminderWingMetrics.digitalFontSize
            )
            .padding(.trailing, ReminderWingMetrics.wingPadding / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// The countdown in one of the three styles, shared by the reminder wings and the music
/// supplement.
struct ReminderCountdownView: View {
    let entry: ReminderEntry
    let now: Date
    let style: ReminderCountdownStyle
    let accent: Color
    let ringDiameter: CGFloat
    let digitalFontSize: CGFloat

    var body: some View {
        switch style {
        case .ring:
            let progress = ReminderSchedule.progress(entry, now: now)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ReminderWingMetrics.ringStrokeWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: ReminderWingMetrics.ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: progress)
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .accessibilityLabel(ReminderSchedule.minutesText(entry, now: now))
        case .digital:
            let text = ReminderSchedule.digitalText(entry, now: now)
            Text(text)
                .font(.system(size: digitalFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: text)
                .lineLimit(1)
        case .minutes:
            Text(ReminderSchedule.minutesText(entry, now: now))
                .font(.system(size: ReminderWingMetrics.minutesFontSize, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
    }
}

// MARK: - Music pairing

/// What the media feature needs to show the reminder beside a playing track, as Atoll does
/// when music owns the closed notch: a "clock" badge on the artwork and the countdown in the
/// right wing. Every size here is measured against the music wing's content height
/// (`ClosedActivityContext.contentHeight`), which is what Atoll passes as `notchHeight`.
enum ReminderMusicSupplement {
    static let badgeSymbol = "clock"
    static let digitalFontSize: CGFloat = 15

    /// The reminder to pair with music, if one is active.
    @MainActor static var activeEntry: ReminderEntry? {
        let model = ReminderLiveActivityModel.shared
        return model.isActivityVisible ? model.activeReminder : nil
    }

    /// "MM:SS" frame: the monospaced-digit 15-pt text plus 18, at least 76.
    static func digitalFrameWidth(for text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: digitalFontSize, weight: .semibold)
        return max(ReminderWingMetrics.measure(text, font: font) + 18, 76)
    }

    /// "in N min" frame: the 13-pt text plus 18, at least 88.
    static func minutesFrameWidth(for text: String) -> CGFloat {
        ReminderWingMetrics.minutesWidth(for: text)
    }

    /// Ring frame: the ring plus 4, at least 26.
    static func ringFrameWidth(notchHeight: CGFloat) -> CGFloat {
        max(ReminderWingMetrics.ringDiameter(closedHeight: notchHeight) + 4, 26)
    }

    /// Right-wing width while paired: at least `baseWidth`, else 16 pt plus the countdown.
    @MainActor static func rightWingWidth(baseWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        let model = ReminderLiveActivityModel.shared
        guard let entry = activeEntry else { return baseWidth }
        let content: CGFloat = switch model.settings.reminderPresentationStyle {
        case .ring:
            ReminderWingMetrics.ringDiameter(closedHeight: notchHeight)
        case .digital:
            digitalFrameWidth(for: ReminderSchedule.digitalText(entry, now: model.now))
        case .minutes:
            minutesFrameWidth(for: ReminderSchedule.minutesText(entry, now: model.now))
        }
        return max(baseWidth, ReminderWingMetrics.wingPadding + content)
    }

    /// Album-art badge side: 36 % of the artwork, never under 13 pt.
    static func badgeSize(artworkSize: CGFloat) -> CGFloat {
        max(13, artworkSize * 0.36)
    }

    /// The badge hangs off the artwork's bottom-trailing corner by a fifth / a quarter of itself.
    static func badgeOffset(badgeSize: CGFloat) -> CGSize {
        CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
    }
}

/// The countdown drawn in the music activity's right wing while a reminder is active.
struct ReminderMusicSupplementView: View {
    @ObservedObject var model: ReminderLiveActivityModel = .shared
    /// The music wing's content height (`ClosedActivityContext.contentHeight`).
    let notchHeight: CGFloat

    var body: some View {
        Group {
            if let entry = model.activeReminder, model.isActivityVisible {
                countdown(for: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func countdown(for entry: ReminderEntry) -> some View {
        let accent = model.accent(for: entry)
        switch model.settings.reminderPresentationStyle {
        case .ring:
            let diameter = ReminderWingMetrics.ringDiameter(closedHeight: notchHeight)
            let progress = ReminderSchedule.progress(entry, now: model.now)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ReminderWingMetrics.ringStrokeWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: ReminderWingMetrics.ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: progress)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: ReminderMusicSupplement.ringFrameWidth(notchHeight: notchHeight), height: notchHeight)
        case .digital:
            let text = ReminderSchedule.digitalText(entry, now: model.now)
            Text(text)
                .font(.system(size: ReminderMusicSupplement.digitalFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: text)
                .lineLimit(1)
                .frame(width: ReminderMusicSupplement.digitalFrameWidth(for: text), alignment: .trailing)
                .frame(height: notchHeight)
        case .minutes:
            let text = ReminderSchedule.minutesText(entry, now: model.now)
            Text(text)
                .font(.system(size: ReminderWingMetrics.minutesFontSize, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(width: ReminderMusicSupplement.minutesFrameWidth(for: text), alignment: .trailing)
                .frame(height: notchHeight)
        }
    }
}

/// The "clock" badge on the album art while a reminder is paired with music: a black disc
/// with the glyph at 55 % in the reminder colour, a soft shadow, and an opacity + scale
/// transition, as in Atoll.
struct ReminderMusicBadgeView: View {
    @ObservedObject var model: ReminderLiveActivityModel = .shared
    let size: CGFloat

    var body: some View {
        if let entry = model.activeReminder, model.isActivityVisible, size > 0 {
            ZStack {
                Circle().fill(Color.black)
                Image(systemName: ReminderMusicSupplement.badgeSymbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(model.accent(for: entry))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        }
    }
}
