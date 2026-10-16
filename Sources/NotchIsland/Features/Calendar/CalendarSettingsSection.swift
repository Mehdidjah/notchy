import AppKit
import EventKit
import SwiftUI

/// Calendar rows for the Settings window, laid out like Atoll's Calendar pane. Returns several
/// `Section`s, so embed it inside a `Form`.
///
/// As in Atoll, while calendar or reminder access is missing the pane shows only the red
/// notice with "Request Access" and "Open System Settings"; once both are granted it shows
/// Permissions, "Show calendar", Event List, All-Day Events, Reminder Live Activity,
/// Third-party Calendar Integration and Select Calendars.
struct CalendarSettingsSection: View {
    @ObservedObject private var settings: CalendarSettings
    @ObservedObject private var store: CalendarStore

    init(settings: CalendarSettings = .shared, store: CalendarStore = .shared) {
        _settings = ObservedObject(wrappedValue: settings)
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        Group {
            if !store.hasEventAccess || !store.hasReminderAccess {
                accessNotice
            } else {
                grantedContent
            }
        }
        .onAppear {
            // As in Atoll, opening the Calendar pane asks for access the user has not decided on.
            store.refreshAuthorizationStatus()
            Task {
                if store.canRequestAccess {
                    await store.requestAccess()
                } else {
                    await store.reloadCalendars()
                }
            }
        }
    }

    // MARK: - Access missing

    private var accessNotice: some View {
        Section {
            Text("Calendar or Reminder access is denied. Please enable it in System Settings.")
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
            HStack {
                Button("Request Access") {
                    Task { await store.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRequestingAccess)
                Button("Open System Settings") { store.openPrivacySettings() }
            }
        }
    }

    // MARK: - Access granted

    @ViewBuilder
    private var grantedContent: some View {
        Section("Permissions") {
            HStack {
                Text("Calendars")
                Spacer()
                Text(Self.statusText(store.eventAuthorization))
                    .foregroundStyle(Self.statusColor(store.eventAuthorization))
            }
            HStack {
                Text("Reminders")
                Spacer()
                Text(Self.statusText(store.reminderAuthorization))
                    .foregroundStyle(Self.statusColor(store.reminderAuthorization))
            }
        }

        Section {
            Toggle("Show calendar", isOn: $settings.showCalendar)
        }

        Section("Event List") {
            Toggle("Hide completed reminders", isOn: $settings.hideCompletedReminders)
            Toggle("Show full event titles", isOn: $settings.showFullEventTitles)
            Toggle("Auto-scroll to next event", isOn: $settings.autoScrollToNextEvent)
        }

        Section("All-Day Events") {
            Toggle("Hide all-day events", isOn: $settings.hideAllDayEvents)
                .disabled(!settings.showCalendar)
            Text("Turn this off to include all-day entries in the notch calendar and reminder live activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("Reminder Live Activity") {
            Toggle("Enable reminder live activity", isOn: $settings.enableReminderLiveActivity)
            Picker("Countdown style", selection: $settings.reminderPresentationStyle) {
                ForEach(ReminderCountdownStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.enableReminderLiveActivity)
            HStack {
                Text("Notify before")
                Slider(
                    value: Binding(
                        get: { Double(settings.reminderLeadTime) },
                        set: { settings.reminderLeadTime = Int($0) }
                    ),
                    in: Double(CalendarSettings.leadTimeRange.lowerBound)...Double(CalendarSettings.leadTimeRange.upperBound),
                    step: 1
                )
                .disabled(!settings.enableReminderLiveActivity)
                Text("\(settings.reminderLeadTime) min")
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            HStack {
                Text("Sneak peek duration")
                Slider(
                    value: $settings.reminderSneakPeekDuration,
                    in: CalendarSettings.sneakPeekDurationRange,
                    step: 1
                )
                .disabled(!settings.enableReminderLiveActivity)
                Text("\(Int(settings.reminderSneakPeekDuration)) s")
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }

        Section {
            Toggle(isOn: $settings.enableThirdPartyCalendarApp) {
                HStack {
                    Image(systemName: "ellipsis.calendar")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Enable third-party calendar app launch")
                }
            }
            if settings.enableThirdPartyCalendarApp {
                Picker("Calendar App", selection: $settings.selectedCalendarApp) {
                    ForEach(ThirdPartyCalendarApp.allCases) { app in
                        HStack {
                            CalendarAppIcon(app: app)
                            Text(app.displayName)
                        }
                        .tag(app)
                    }
                }
                if settings.selectedCalendarApp == .fantastical {
                    Picker("Default View", selection: $settings.fantasticalDefaultView) {
                        ForEach(FantasticalViewStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }
            }
        } header: {
            Text("Third-party Calendar Integration")
        } footer: {
            Text("When enabled, clicking on calendar events will open the selected third-party calendar app instead of Apple Calendar.")
        }

        Section("Select Calendars") {
            let grouped = Dictionary(grouping: store.calendars, by: \.accountName)
            ForEach(grouped.keys.sorted(), id: \.self) { account in
                let calendars = grouped[account] ?? []
                Section {
                    ForEach(calendars) { calendar in
                        Toggle(isOn: Binding(
                            get: { store.isSelected(calendar) },
                            set: { store.setSelected([calendar], isSelected: $0) }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(calendar.color.color)
                                    .frame(width: 8, height: 8)
                                Text(calendar.title)
                            }
                        }
                        .disabled(!settings.showCalendar)
                    }
                } header: {
                    HStack {
                        Text(account)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { calendars.allSatisfy(store.isSelected) },
                            set: { store.setSelected(calendars, isSelected: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(!settings.showCalendar)
                    }
                }
            }
        }
    }

    static func statusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "Full Access"
        case .writeOnly: "Write Only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not Determined"
        default: "Unknown"
        }
    }

    static func statusColor(_ status: EKAuthorizationStatus) -> Color {
        switch status {
        case .fullAccess: .green
        case .writeOnly: .yellow
        case .denied, .restricted: .red
        default: .secondary
        }
    }
}

/// The installed app's 16-pt icon (rounded at 20 %), or Atoll's fallback glyph when the app
/// is not installed: a red "calendar.badge.clock" for Fantastical, a blue
/// "calendar.badge.plus" for Notion Calendar.
private struct CalendarAppIcon: View {
    let app: ThirdPartyCalendarApp
    private let size: CGFloat = 16

    var body: some View {
        Group {
            if let icon = Self.icon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: app == .fantastical ? "calendar.badge.clock" : "calendar.badge.plus")
                    .foregroundStyle(app == .fantastical ? Color.red : Color.blue)
            }
        }
        .frame(width: size, height: size)
    }

    private static func icon(for app: ThirdPartyCalendarApp) -> NSImage? {
        for identifier in app.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return nil
    }
}
