import SwiftUI

/// Atoll's standalone calendar, shown on Home when no media player is: a month picker on
/// the left and the selected day's events as cards on the right, two equal panes 12 pt apart.
struct CalendarStandalonePanel: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: CalendarSettings
    /// Total height, from `CalendarLayout.standaloneHeight`.
    let height: CGFloat
    /// Changes each time the island opens; the grid then re-centres on today.
    var openGeneration = 0

    @State private var displayedMonth = CalendarMonthGrid.startOfMonth(Date())
    @State private var gridScrollTarget: Date?

    private let paneSpacing: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = max((geometry.size.width - paneSpacing) / 2, 0)
            let paneHeight = max(0, geometry.size.height)
            HStack(alignment: .top, spacing: paneSpacing) {
                monthPane
                    .frame(width: paneWidth, alignment: .topLeading)
                    .frame(height: paneHeight, alignment: .topLeading)
                    .layoutPriority(1)
                eventsPane
                    .frame(width: paneWidth, alignment: .topLeading)
                    .frame(height: paneHeight, alignment: .topLeading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .frame(height: height)
        .clipped()
        .onAppear(perform: centreOnToday)
        .onChange(of: openGeneration) { _, _ in centreOnToday() }
        .onChange(of: store.selectedDay) { _, day in
            let month = CalendarMonthGrid.startOfMonth(day)
            guard month != displayedMonth else { return }
            withAnimation(.smooth(duration: 0.22)) {
                displayedMonth = month
            }
        }
    }

    /// Atoll, on appear and whenever the notch opens: today's month, centred on today. The
    /// slot resets the store's selection to today at the same moment.
    private func centreOnToday() {
        let today = Calendar.current.startOfDay(for: Date())
        displayedMonth = CalendarMonthGrid.startOfMonth(today)
        gridScrollTarget = today
    }

    // MARK: Month picker

    private var monthPane: some View {
        GeometryReader { geometry in
            let viewportHeight = max(96, geometry.size.height - 56)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(displayedMonth.formatted(.dateTime.month(.wide)))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text(displayedMonth.formatted(.dateTime.year()))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(CalendarPalette.secondaryText)
                    }
                    .lineLimit(1)
                    Spacer()
                    HStack(spacing: 6) {
                        monthButton(systemImage: "chevron.left", label: "Previous month", offset: -1)
                        monthButton(systemImage: "chevron.right", label: "Next month", offset: 1)
                    }
                    .foregroundStyle(.white)
                }

                ScrollViewReader { proxy in
                    VStack(spacing: 6) {
                        LazyVGrid(columns: gridColumns, spacing: 6) {
                            ForEach(Array(CalendarMonthGrid.weekdayInitials().enumerated()), id: \.offset) { _, symbol in
                                Text(symbol)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color(white: 0.55))
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        ZStack {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: gridColumns, spacing: 6) {
                                    ForEach(CalendarMonthGrid.days(for: displayedMonth), id: \.self) { day in
                                        dayCell(day)
                                            .id(Calendar.current.startOfDay(for: day))
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            .onChange(of: gridScrollTarget) { _, target in
                                guard let target else { return }
                                centre(on: target, proxy: proxy)
                            }
                            .onAppear {
                                if let target = gridScrollTarget { centre(on: target, proxy: proxy) }
                            }

                            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                                .frame(maxHeight: .infinity, alignment: .top)
                            LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: max(0, viewportHeight - 22))
                        .clipped()
                    }
                    .frame(height: viewportHeight)
                }
                .frame(height: viewportHeight)
                .clipped()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .clipped()
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7)
    }

    private func monthButton(systemImage: String, label: String, offset: Int) -> some View {
        Button {
            showMonth(offset: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: store.selectedDay)
        let isToday = calendar.isDateInToday(day)
        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                store.select(day: day)
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(CalendarPalette.accent)
                        .frame(width: 28, height: 28)
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(dayColor(inMonth: inMonth, selected: isSelected, today: isToday))
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayColor(inMonth: Bool, selected: Bool, today: Bool) -> Color {
        if selected { return .white }
        if !inMonth { return Color(white: 0.35) }
        if today { return CalendarPalette.accent }
        return .white
    }

    /// Chevrons move a month and select its first day.
    private func showMonth(offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        let start = CalendarMonthGrid.startOfMonth(month)
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = start
            store.select(day: start)
        }
    }

    private func centre(on target: Date, proxy: ScrollViewProxy) {
        let day = Calendar.current.startOfDay(for: target)
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(day, anchor: .center)
            }
            if gridScrollTarget == day { gridScrollTarget = nil }
        }
    }

    // MARK: Events

    @ViewBuilder
    private var eventsPane: some View {
        let visible = CalendarEventFilter.visibleEntries(
            store.events,
            hideCompletedReminders: settings.hideCompletedReminders,
            hideAllDayEvents: settings.hideAllDayEvents
        )
        Group {
            if !store.hasAnyAccess {
                CalendarAccessPromptView(store: store)
            } else if visible.isEmpty {
                CalendarEmptyEventsView(day: store.selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarEventCardList(store: store, settings: settings, entries: visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// The standalone view's event cards: rounded 14-pt cards in a plain list under the same
/// floating all-day strip as the compact list.
struct CalendarEventCardList: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var settings: CalendarSettings
    let entries: [CalendarEntry]

    var body: some View {
        let parts = CalendarEventFilter.split(entries)
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                List {
                    ForEach(parts.timed) { entry in
                        TimelineView(.everyMinute) { context in
                            card(for: entry, now: context.date)
                        }
                        .id(entry.id)
                        .padding(.bottom, 8)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.never)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.top, parts.allDay.isEmpty ? 0 : CalendarLayout.allDayListInset)
                .modifier(CalendarAutoScrollModifier(
                    proxy: proxy,
                    timed: parts.timed,
                    day: store.selectedDay,
                    enabled: settings.autoScrollToNextEvent
                ))
            }

            if !parts.allDay.isEmpty {
                CalendarAllDayStrip(
                    entries: parts.allDay,
                    onOpen: { store.open($0) },
                    onToggleReminder: { store.setReminderCompleted($0, completed: $1) }
                )
                .background(Color.black.opacity(0.95))
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func card(for entry: CalendarEntry, now: Date) -> some View {
        if entry.kind.isReminder {
            Button {
                store.open(entry)
            } label: {
                reminderCard(entry)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        } else {
            eventCard(entry, now: now)
                .contentShape(Rectangle())
                .onTapGesture { store.open(entry) }
                .padding(.horizontal, 2)
        }
    }

    private func reminderCard(_ entry: CalendarEntry) -> some View {
        let completed = entry.kind.isCompletedReminder
        return HStack(spacing: 10) {
            CalendarReminderToggle(isOn: completed, color: entry.calendar.color.color) {
                store.setReminderCompleted(entry, completed: $0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(settings.showFullEventTitles ? nil : 2)
                if entry.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .foregroundStyle(CalendarPalette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if !entry.isAllDay {
                Text(entry.start, style: .time)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.75))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .opacity(completed ? 0.55 : 1)
    }

    private func eventCard(_ entry: CalendarEntry, now: Date) -> some View {
        let endedToday = entry.status(at: now) == .ended && Calendar.current.isDateInToday(entry.start)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.calendar.color.color)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(settings.showFullEventTitles ? nil : 2)
                if let location = entry.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(CalendarPalette.secondaryText)
                        .lineLimit(1)
                }
                if let url = entry.conferenceURL {
                    CalendarConferenceJoinButton(entry: entry, url: url, now: now) { store.joinConference($0) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                } else {
                    Text(entry.start, style: .time)
                        .font(.caption)
                        .foregroundStyle(.white)
                    Text(entry.end, style: .time)
                        .font(.caption2)
                        .foregroundStyle(CalendarPalette.secondaryText)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .opacity(endedToday ? 0.6 : 1)
    }
}
