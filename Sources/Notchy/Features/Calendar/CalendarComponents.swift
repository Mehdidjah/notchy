import SwiftUI

// MARK: - Reminder toggle

/// A 14-pt ring in the list's colour that fills with an 8-pt dot when the reminder is done.
struct CalendarReminderToggle: View {
    let isOn: Bool
    let color: Color
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isOn)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                // Keeps the hollow centre clickable.
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Conference join button

/// "Join Zoom" / "Rejoin Teams" pill in the provider's colour, live from 15 minutes before
/// the start and greyed out before that.
struct CalendarConferenceJoinButton: View {
    let entry: CalendarEntry
    let url: URL
    let now: Date
    let onJoin: (URL) -> Void

    var body: some View {
        let provider = ConferenceProvider.detect(from: url)
        let joinable = entry.isJoinable(at: now)
        let verb = entry.status(at: now) == .inProgress ? "Rejoin" : "Join"
        Button {
            onJoin(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.displayName.isEmpty ? verb : "\(verb) \(provider.displayName)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(joinable ? Color.white : Color(white: 0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(joinable ? provider.tint.opacity(0.85) : Color.gray.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!joinable)
        .help(joinable ? "Join the meeting" : "Meeting starts at \(entry.start.formatted(date: .omitted, time: .shortened))")
    }
}

// MARK: - All-day strip

/// One horizontally scrolling row of all-day chips, floated over the top of the event list
/// so any number of all-day items costs a single 28-pt row.
struct CalendarAllDayStrip: View {
    let entries: [CalendarEntry]
    let onOpen: (CalendarEntry) -> Void
    let onToggleReminder: (CalendarEntry, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        chip(for: entry)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, CalendarLayout.allDayVerticalPadding)
            }
            .frame(height: CalendarLayout.allDayChipRowHeight)
            .clipped()

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func chip(for entry: CalendarEntry) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.calendar.color.color)
                .frame(width: 8, height: 8)
            Text(entry.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
            if entry.isAllDay {
                Text("All-day")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(1)
            }
            if entry.kind.isReminder {
                CalendarReminderToggle(
                    isOn: entry.kind.isCompletedReminder,
                    color: entry.calendar.color.color
                ) { onToggleReminder(entry, $0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, CalendarLayout.allDayVerticalPadding)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture { onOpen(entry) }
    }
}

// MARK: - Empty state

struct CalendarEmptyEventsView: View {
    let day: Date

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(CalendarPalette.secondaryText)
                .padding(.bottom, 7)
            Text(Calendar.current.isDateInToday(day) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundStyle(CalendarPalette.secondaryText)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Access prompt

/// Shown in the event area until EventKit access is granted, styled like the empty state so
/// the panel keeps its look. The compact panel drops the explanatory line to fit 120 pt.
struct CalendarAccessPromptView: View {
    @ObservedObject var store: CalendarStore
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(CalendarPalette.secondaryText)
                .padding(.bottom, 7)
            Text("Calendar access needed")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            if !compact {
                Text(store.canRequestAccess
                     ? "Allow access to see your events and reminders."
                     : "Turn on Calendars in Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(CalendarPalette.secondaryText)
                    .padding(.top, 1)
            }
            Button {
                if store.canRequestAccess {
                    Task { await store.requestAccess() }
                } else {
                    store.openPrivacySettings()
                }
            } label: {
                Text(store.canRequestAccess ? "Allow Access" : "Open Settings")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(CalendarPalette.accent.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .disabled(store.isRequestingAccess)
            .padding(.top, compact ? 6 : 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Auto-scroll

/// Event-list auto-scroll: on appear and on a day change, centre the running or next
/// event; when events first arrive after the list appeared, do it once more.
struct CalendarAutoScrollModifier: ViewModifier {
    let proxy: ScrollViewProxy
    let timed: [CalendarEntry]
    let day: Date
    let enabled: Bool
    @State private var didInitialScroll = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                scroll()
                if !timed.isEmpty { didInitialScroll = true }
            }
            .onChange(of: day) { _, _ in scroll() }
            .onChange(of: timed.isEmpty) { wasEmpty, isEmpty in
                guard wasEmpty, !isEmpty, !didInitialScroll else { return }
                scroll()
                didInitialScroll = true
            }
            .onChange(of: timed) { _, _ in
                if !didInitialScroll { scroll() }
            }
    }

    private func scroll() {
        guard enabled else { return }
        let reference = CalendarEventFilter.scrollReference(for: day)
        guard let target = CalendarEventFilter.scrollTarget(in: timed, at: reference) else { return }
        let id = target.id
        let proxy = proxy
        // On the next main-loop turn, after the list has measured its rows; no animation.
        DispatchQueue.main.async {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
