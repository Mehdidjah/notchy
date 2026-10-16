import SwiftUI

/// Compact calendar beside the media player: month and year beside a scrubbable
/// date strip, above the day's events, 120 pt tall. The strip stays visible so the dates
/// show even on a day without events. Days with events are
/// tinted in their calendar's colour; a day without any shows just the dates.
struct CalendarCompactPanel: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: CalendarSettings
    let hapticsEnabled: Bool
    private let headerExpanded = true

    var body: some View {
        let visible = CalendarEventFilter.visibleEntries(
            store.events,
            hideCompletedReminders: settings.hideCompletedReminders,
            hideAllDayEvents: settings.hideAllDayEvents
        )
        VStack(spacing: CalendarLayout.compactSectionSpacing) {
            header
            if !store.hasAnyAccess {
                CalendarAccessPromptView(store: store, compact: true)
            } else if !visible.isEmpty {
                CalendarCompactEventList(store: store, settings: settings, entries: visible)
                    .transition(.opacity)
            }
        }
        .frame(height: CalendarLayout.compactHeight, alignment: .top)
        .animation(.smooth(duration: 0.2), value: visible.isEmpty)
    }

    private var header: some View {
        let day = store.selectedDay
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if headerExpanded {
                    Text(day.formatted(.dateTime.month(.abbreviated)))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(day.formatted(.dateTime.year()))
                        .font(.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(CalendarPalette.secondaryText)
                } else {
                    Text(Self.collapsedTitle(for: day))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: CalendarLayout.headerLabelWidth, alignment: .leading)

            ZStack {
                CalendarDayStripPicker(
                    selection: day,
                    hapticsEnabled: hapticsEnabled,
                    eventDays: store.hasAnyAccess ? store.eventDays : [:],
                    onSelect: { store.select(day: $0) }
                )
                .frame(maxWidth: .infinity)

                // Edge fades hint that the strip scrolls; subtle so they never hide a date.
                LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: CalendarLayout.dateStripFadeWidth)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LinearGradient(colors: [.clear, Color.black.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: CalendarLayout.dateStripFadeWidth)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: headerExpanded ? CalendarLayout.dateStripHeight : 0)
            .opacity(headerExpanded ? 1 : 0)
            .allowsHitTesting(headerExpanded)
            .clipped()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .contentShape(Rectangle())
    }

    /// "Wed, Oct 15".
    static func collapsedTitle(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated)) + ", "
            + day.formatted(.dateTime.month(.abbreviated)) + " "
            + day.formatted(.dateTime.day())
    }
}

// MARK: - Date strip

/// Horizontal strip of days (a week back, two weeks ahead) that snaps the selected day to the
/// centre. Click a day, scroll with the trackpad, or drag with the mouse to scrub.
struct CalendarDayStripPicker: View {
    let selection: Date
    let hapticsEnabled: Bool
    /// Midnight of each day with events, with the colour of its first entry.
    var eventDays: [Date: CalendarColor] = [:]
    let onSelect: (Date) -> Void
    var strip = CalendarDayStrip()

    @State private var scrollID: Int?
    @State private var hapticTrigger = false
    /// Set when the code moves the strip, so the resulting scroll does not count as a pick.
    @State private var programmaticScroll = false
    @State private var dragAnchor: Int?
    @State private var cellWidth: CGFloat = 40

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<strip.itemCount, id: \.self) { index in
                    if strip.isSpacer(index) {
                        Color.clear
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        dayCell(index: index, day: strip.day(at: index, today: today))
                    }
                }
            }
            .frame(height: CalendarLayout.dateStripHeight)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: hapticTrigger)
        .onAppear {
            programmaticScroll = true
            scrollID = strip.index(of: selection, today: today)
        }
        .onChange(of: scrollID) { _, newValue in
            if programmaticScroll {
                programmaticScroll = false
                return
            }
            userScrolled(to: newValue, today: today)
        }
        .onChange(of: selection) { _, newValue in
            let target = strip.index(of: newValue, today: today)
            guard scrollID != target else { return }
            programmaticScroll = true
            withAnimation { scrollID = target }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragAnchor == nil { dragAnchor = scrollID }
                    guard let anchor = dragAnchor, cellWidth > 1 else { return }
                    let steps = Int((-value.translation.width / cellWidth).rounded())
                    let target = min(max(strip.dayIndices.lowerBound, anchor + steps), strip.dayIndices.upperBound - 1)
                    guard target != scrollID else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { scrollID = target }
                }
                .onEnded { _ in dragAnchor = nil }
        )
    }

    private func dayCell(index: Int, day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let eventColor = eventDays[calendar.startOfDay(for: day)].map { $0.adjustedToLuminance(0.6).color }
        return Button {
            if scrollID != index {
                programmaticScroll = true
                withAnimation { scrollID = index }
            }
            onSelect(day)
            if hapticsEnabled { hapticTrigger.toggle() }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : CalendarPalette.secondaryText)
                ZStack {
                    Circle()
                        .fill(isToday ? CalendarPalette.accent : .clear)
                        .frame(width: 20, height: 20)
                    Text(day.formatted(.dateTime.day()))
                        .font(.body)
                        .fontWeight(eventColor == nil ? .medium : .semibold)
                        .foregroundStyle(Self.numberStyle(isToday: isToday, isSelected: isSelected, eventColor: eventColor))
                }
                .frame(width: 20, height: 20)
                .overlay(alignment: .bottom) {
                    // A small dot under the number marks a day with events.
                    Circle()
                        .fill(eventColor ?? .clear)
                        .frame(width: 4, height: 4)
                        .offset(y: 6)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 7)
            .padding(.horizontal, 4)
            .background(isSelected ? CalendarPalette.accentBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (eventColor == nil ? "" : ", has events"))
        .id(index)
        .background {
            if index == strip.dayIndices.lowerBound {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cellWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in cellWidth = width }
                }
            }
        }
    }

    /// Today keeps its white number on the accent circle; other event days take the event's
    /// colour so they stand out from empty days.
    static func numberStyle(isToday: Bool, isSelected: Bool, eventColor: Color?) -> Color {
        if isToday { return .white }
        if let eventColor { return eventColor }
        return isSelected ? .white : Color(white: 0.65)
    }

    private func userScrolled(to index: Int?, today: Date) {
        guard let index, strip.dayIndices.contains(index) else { return }
        let day = strip.day(at: index, today: today)
        guard !Calendar.current.isDate(day, inSameDayAs: selection) else { return }
        onSelect(day)
        if hapticsEnabled { hapticTrigger.toggle() }
    }
}

// MARK: - Event list

/// The selected day's entries as small one-line descriptions: a colour bar, the title and
/// the time, all-day items first. Scrolls when the day has more than fit, centred on the
/// running or next event.
struct CalendarCompactEventList: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: CalendarSettings
    /// Already filtered by the hide settings.
    let entries: [CalendarEntry]

    var body: some View {
        let parts = CalendarEventFilter.split(entries)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: CalendarLayout.compactRowSpacing) {
                    ForEach(parts.allDay + parts.timed) { entry in
                        TimelineView(.everyMinute) { context in
                            CalendarCompactEventRow(
                                entry: entry,
                                now: context.date,
                                showsFullTitle: settings.showFullEventTitles,
                                onOpen: { store.open(entry) },
                                onToggleReminder: { store.setReminderCompleted(entry, completed: $0) },
                                onJoin: { store.joinConference($0) }
                            )
                        }
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
            .modifier(CalendarAutoScrollModifier(
                proxy: proxy,
                timed: parts.timed,
                day: store.selectedDay,
                enabled: settings.autoScrollToNextEvent
            ))
        }
    }
}

/// One entry as a single compact line on a faint tint of its calendar colour.
struct CalendarCompactEventRow: View {
    let entry: CalendarEntry
    let now: Date
    let showsFullTitle: Bool
    let onOpen: () -> Void
    let onToggleReminder: (Bool) -> Void
    let onJoin: (URL) -> Void
    @State private var isHovered = false

    var body: some View {
        let tint = entry.calendar.color.color
        let isRunning = !entry.isAllDay && entry.isActive(at: now)
        HStack(spacing: 6) {
            if entry.kind.isReminder {
                CalendarReminderToggle(isOn: entry.kind.isCompletedReminder, color: tint, onToggle: onToggleReminder)
                    .scaleEffect(0.85)
            } else {
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: 12)
            }
            Text(entry.title.isEmpty ? "Untitled" : entry.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(showsFullTitle ? 2 : 1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let url = entry.conferenceURL, entry.isJoinable(at: now), entry.status(at: now) != .ended {
                Button {
                    onJoin(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 14)
                        .background(Capsule().fill(ConferenceProvider.detect(from: url).tint.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .help("Join the meeting")
            }
            Text(timeText(isRunning: isRunning))
                .font(.system(size: 10, weight: isRunning ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isRunning ? tint : CalendarPalette.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(isHovered ? 0.24 : 0.14))
        )
        .opacity(dimmed ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(timeText(isRunning: isRunning))")
        .accessibilityAddTraits(.isButton)
    }

    /// Finished events of today and completed reminders fade back.
    private var dimmed: Bool {
        if entry.kind.isCompletedReminder { return true }
        return !entry.isAllDay && !entry.kind.isReminder && entry.status(at: now) == .ended
    }

    private func timeText(isRunning: Bool) -> String {
        if entry.isAllDay { return "All day" }
        if isRunning, !entry.kind.isReminder { return "Now" }
        return entry.start.formatted(date: .omitted, time: .shortened)
    }
}
