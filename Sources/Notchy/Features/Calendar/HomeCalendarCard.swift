import AppKit
import SwiftUI

/// Home-tab date card: the weekday in red beside the month, today's date in large figures,
/// and under it the next or current timed entry of the day once calendar access is granted
/// (an "Allow" button while access can still be asked for). A click opens that entry, or the
/// calendar app when there is none.
struct HomeCalendarCard: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var store: CalendarStore
    @ObservedObject private var settings: CalendarSettings

    init(model: NotchViewModel, store: CalendarStore = .shared, settings: CalendarSettings = .shared) {
        self.model = model
        _store = ObservedObject(wrappedValue: store)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let next = nextEntry(at: now)
            HomeCard(padding: EdgeInsets(top: 12, leading: 8, bottom: 11, trailing: 8)) {
                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Text(now.formatted(.dateTime.weekday(.abbreviated)))
                            .foregroundStyle(HomeCardPalette.red)
                        Text(now.formatted(.dateTime.month(.abbreviated)))
                            .foregroundStyle(HomeCardPalette.primaryText)
                    }
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(now.formatted(.dateTime.day()))
                        .font(.system(size: next == nil ? 66 : 54, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxHeight: .infinity)
                    footer(next: next, now: now)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: .continuous))
            .onTapGesture { open(next) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .onAppear {
            store.refreshAuthorizationStatus()
            store.resetToToday()
        }
        .onChange(of: model.state.showsShelfContent) { _, isOpen in
            store.resetToToday()
            if isOpen { store.refreshAuthorizationStatus() }
        }
    }

    @ViewBuilder
    private func footer(next: CalendarEntry?, now: Date) -> some View {
        if let next {
            HStack(spacing: 4) {
                Circle()
                    .fill(next.calendar.color.color)
                    .frame(width: 5, height: 5)
                Text(next.isActive(at: now) ? "Now" : next.start.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(HomeCardPalette.secondaryText)
                    .fixedSize()
                Text(next.title)
                    .foregroundStyle(HomeCardPalette.primaryText)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
        } else if !store.hasAnyAccess, store.canRequestAccess {
            Button {
                Task { await store.requestAccess() }
            } label: {
                Text("Show Events")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(HomeCardPalette.primaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(store.isRequestingAccess)
        }
    }

    /// The first timed entry today that has not ended, once access is granted.
    private func nextEntry(at now: Date) -> CalendarEntry? {
        guard store.hasAnyAccess, Calendar.current.isDate(store.selectedDay, inSameDayAs: now) else { return nil }
        return CalendarEventFilter.visibleEntries(
            store.events,
            hideCompletedReminders: settings.hideCompletedReminders,
            hideAllDayEvents: true
        )
        .filter { !$0.isAllDay && ($0.end > now || $0.isActive(at: now)) }
        .min { $0.start < $1.start }
    }

    private func open(_ entry: CalendarEntry?) {
        if let entry {
            store.open(entry)
        } else if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
}
