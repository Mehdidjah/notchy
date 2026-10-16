import ServiceManagement
import SwiftUI

/// Settings panes in sidebar order and grouping. Each pane has a gradient tile tint and an
/// SF Symbol.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance
    case media, liveActivities, devices
    case controls, battery, faceCheck
    case timer, calendar, notes
    case clipboard, colorPicker, shelf, downloads, shortcuts
    case stats
    case permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .media: "Media"
        case .liveActivities: "Live Activities"
        case .devices: "Devices"
        case .controls: "Controls"
        case .battery: "Battery"
        case .faceCheck: "Face Check"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .notes: "Notes"
        case .clipboard: "Clipboard"
        case .colorPicker: "Color Picker"
        case .shelf: "Shelf"
        case .downloads: "Downloads"
        case .shortcuts: "Shortcuts"
        case .stats: "Stats"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .appearance: "paintpalette"
        case .media: "play.laptopcomputer"
        case .liveActivities: "waveform.path.ecg"
        case .devices: "headphones"
        case .controls: "dial.medium.fill"
        case .battery: "battery.100.bolt"
        case .faceCheck: "faceid"
        case .timer: "timer"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .clipboard: "clipboard"
        case .colorPicker: "eyedropper"
        case .shelf: "books.vertical"
        case .downloads: "square.and.arrow.down"
        case .shortcuts: "keyboard"
        case .stats: "chart.xyaxis.line"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .blue
        case .appearance: .purple
        case .media: .green
        case .liveActivities: .pink
        case .devices: Color(red: 0.10, green: 0.11, blue: 0.12)
        case .controls: .indigo
        case .battery: Color(red: 0.202, green: 0.783, blue: 0.348)
        case .faceCheck: .teal
        case .timer: .red
        case .calendar: .cyan
        case .notes: Color(red: 0.979, green: 0.716, blue: 0.153)
        case .clipboard: .mint
        case .colorPicker: .accentColor
        case .shelf: .brown
        case .downloads: .gray
        case .shortcuts: .orange
        case .stats: .teal
        case .permissions: .blue
        case .about: .secondary
        }
    }

    var isBeta: Bool { self == .downloads }

    /// Extra words the sidebar search matches.
    var keywords: String {
        switch self {
        case .general: "hover dwell close delay gestures swipe haptics tabs fullscreen launch login"
        case .appearance: "width shadow screen recording capture peek sneak"
        case .media: "music spotify player lyrics visualizer artwork"
        case .liveActivities: "focus privacy camera microphone caps lock download"
        case .devices: "bluetooth airpods headphones"
        case .controls: "volume brightness hud osd media keys"
        case .battery: "charging low full power"
        case .faceCheck: "face camera recognition enrol enroll unlock privacy"
        case .clipboard: "history capture retention sensitive paste"
        case .shortcuts: "keyboard hotkey"
        case .stats: "cpu memory gpu network disk"
        default: ""
        }
    }

    /// Sidebar group headings; nil means no heading.
    var group: String? {
        switch self {
        case .general, .appearance: nil
        case .media, .liveActivities, .devices: "Media & Display"
        case .controls, .battery, .faceCheck: "System"
        case .timer, .calendar, .notes: "Productivity"
        case .clipboard, .colorPicker, .shelf, .downloads, .shortcuts: "Utilities"
        case .stats: "Developer"
        case .permissions, .about: "Info"
        }
    }

    static var groupOrder: [String?] { [nil, "Media & Display", "System", "Productivity", "Utilities", "Developer", "Info"] }
}

/// Hosts feature-provided settings. Feature modules register a section view per pane when they
/// start; panes without one show a short note.
@MainActor
final class SettingsSectionRegistry: ObservableObject {
    static let shared = SettingsSectionRegistry()

    @Published private(set) var sections: [SettingsPane: [(id: String, view: AnyView)]] = [:]

    func register<Content: View>(_ pane: SettingsPane, id: String, @ViewBuilder content: () -> Content) {
        var list = sections[pane] ?? []
        list.removeAll { $0.id == id }
        list.append((id, AnyView(content())))
        sections[pane] = list
    }
}

struct SettingsView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var settings: UserSettings
    @ObservedObject var permissions: PermissionManager
    @ObservedObject private var registry = SettingsSectionRegistry.shared
    @State private var selection: SettingsPane? = .general
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                Divider()
                List(selection: $selection) {
                    ForEach(SettingsPane.groupOrder, id: \.self) { group in
                        let panes = visiblePanes.filter { $0.group == group }
                        if !panes.isEmpty {
                            if let group {
                                Section(group) { rows(panes) }
                            } else {
                                Section { rows(panes) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 44)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            detail(for: selection ?? .general)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .formStyle(.grouped)
                .navigationTitle((selection ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 600)
        .onChange(of: searchText) { _, _ in
            if let first = visiblePanes.first, !visiblePanes.contains(selection ?? .general) {
                selection = first
            }
        }
    }

    private var visiblePanes: [SettingsPane] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter {
            "\($0.title) \($0.keywords)".localizedCaseInsensitiveContains(query)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $searchText).textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func rows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            HStack(spacing: 10) {
                SettingsTile(symbol: pane.systemImage, tint: pane.tint)
                Text(pane.title)
                if pane.isBeta {
                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                }
            }
            .padding(.vertical, 4)
            .tag(pane)
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: general
        case .appearance: appearance
        case .clipboard: clipboard
        case .permissions: permissionSettings
        case .about: about
        default: featurePane(pane)
        }
    }

    // MARK: Panes

    private var general: some View {
        Form {
            Section("Notch") {
                Toggle("Enable the island", isOn: $settings.notchEnabled)
                    .onChange(of: settings.notchEnabled) { _, enabled in model.setNotchEnabled(enabled) }
                Toggle("Open on hover", isOn: $settings.openOnHover)
                LabeledContent("Minimum hover duration") {
                    HStack {
                        Slider(value: hoverSeconds, in: 0...1, step: 0.1)
                        Text(String(format: "%.1f s", hoverSeconds.wrappedValue)).monospacedDigit().frame(width: 44)
                    }
                }
                .disabled(!settings.openOnHover)
                Stepper("Close delay: \(settings.closeDelayMilliseconds) ms", value: $settings.closeDelayMilliseconds, in: 0...1000, step: 50)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                Toggle("Hide in fullscreen", isOn: $settings.hideInFullscreen)
                Toggle("Reopen on the last tab", isOn: $settings.openLastTab)
                LaunchAtLoginToggle()
            }
            Section("Gesture control") {
                Toggle("Enable gestures", isOn: $settings.gesturesEnabled)
                Toggle("Close gesture", isOn: $settings.closeGestureEnabled)
                    .disabled(!settings.gesturesEnabled)
                Picker("Gesture sensitivity", selection: $settings.gestureSensitivity) {
                    Text("High").tag(100.0)
                    Text("Medium").tag(200.0)
                    Text("Low").tag(300.0)
                }
                .pickerStyle(.segmented)
                .disabled(!settings.gesturesEnabled)
            }
            Section("Tabs") {
                Toggle("Home", isOn: $settings.showHomeTab)
                Toggle("Shelf", isOn: $settings.showShelfTab)
                Toggle("Timer", isOn: $settings.showTimerTab)
                Toggle("Stats", isOn: $settings.showStatsTab)
                Toggle("Notes", isOn: $settings.showNotesTab)
                LabeledContent("Clipboard", value: "Always shown")
            }
        }
    }

    private var appearance: some View {
        Form {
            Section("Notch") {
                LabeledContent("Open width") {
                    HStack {
                        Slider(value: $settings.openNotchWidth, in: NotchTab.defaultOpenWidth...NotchTab.maximumOpenWidth, step: 10)
                        Text("\(Int(settings.openNotchWidth)) pt").monospacedDigit().frame(width: 52)
                        Button("Reset") { settings.openNotchWidth = NotchTab.defaultOpenWidth }
                            .disabled(settings.openNotchWidth == NotchTab.defaultOpenWidth)
                    }
                }
                Toggle("Shadow", isOn: $settings.showShadow)
                Toggle("Hide from screenshots and recordings", isOn: $settings.hideFromScreenCapture)
            }
            Section("Sneak peek") {
                Toggle("Show copied clips under the notch", isOn: $settings.showCapturePeek)
            }
            registeredSections(.appearance)
        }
    }

    private var clipboard: some View {
        Form {
            Section("Capture") {
                Toggle("Save clipboard history", isOn: $settings.captureEnabled)
                Toggle("Manual capture only", isOn: $settings.manualCaptureOnly)
                Stepper("Maximum payload: \(settings.maxPayloadMegabytes) MB", value: $settings.maxPayloadMegabytes, in: 1...500, step: 5)
                Picker("Duplicate copies", selection: $settings.duplicateBehavior) {
                    Text("Move original to front").tag(DuplicateCaptureBehavior.moveOriginalToFront)
                    Text("Store every event").tag(DuplicateCaptureBehavior.storeSeparateEvent)
                }
                Picker("Clicking a clip", selection: $settings.defaultAction) {
                    Text("Pastes it").tag(DefaultClipAction.paste)
                    Text("Copies it").tag(DefaultClipAction.copy)
                    Text("Previews it").tag(DefaultClipAction.preview)
                }
            }
            Section("History") {
                Picker("Delete unprotected clips after", selection: $settings.retentionPreset) {
                    Text("7 days").tag(RetentionPreset.sevenDays)
                    Text("15 days").tag(RetentionPreset.fifteenDays)
                    Text("30 days").tag(RetentionPreset.thirtyDays)
                    Text("90 days").tag(RetentionPreset.ninetyDays)
                    Text("Never").tag(RetentionPreset.forever)
                }
                Stepper("Maximum items: \(settings.maximumItemCount.formatted())", value: $settings.maximumItemCount, in: 100...100_000, step: 100)
                Button("Clear non-protected history", role: .destructive) { model.clearHistoryPreservingProtected() }
            }
            Section("Sensitive content") {
                Toggle("Allow manually saved sensitive clips", isOn: $settings.saveSensitiveContent)
                Text("Password-like values, API keys, tokens, private keys, payment-card numbers, .env secrets and credentialed database URLs are skipped locally by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            registeredSections(.clipboard)
        }
    }

    private var permissionSettings: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { permission in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.displayName)
                            Text(explanation(for: permission)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((permissions.states[permission] ?? .notDetermined).rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateColor(permissions.states[permission] ?? .notDetermined))
                        Button("Settings") { permissions.openSystemSettings(for: permission) }
                    }
                }
            }
            Section {
                Button("Refresh Permission Status") { permissions.refresh() }
                Text("Accessibility lets Notchy paste into the app you came from and handle media keys. Without it, clips are copied instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            registeredSections(.permissions)
        }
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SettingsTile(symbol: "macbook", tint: .blue, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchy").font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Acknowledgements") {
                Text("Notchy brings music, calendar, timers, files and your clipboard to the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            registeredSections(.about)
        }
    }

    private func featurePane(_ pane: SettingsPane) -> some View {
        Form {
            if (registry.sections[pane] ?? []).isEmpty {
                Section {
                    Text("\(pane.title) settings appear here once the feature is installed in this build.")
                        .foregroundStyle(.secondary)
                }
            } else {
                registeredSections(pane)
            }
        }
    }

    @ViewBuilder
    private func registeredSections(_ pane: SettingsPane) -> some View {
        ForEach(registry.sections[pane] ?? [], id: \.id) { entry in
            entry.view
        }
    }

    private var hoverSeconds: Binding<Double> {
        Binding(
            get: { Double(settings.hoverDelayMilliseconds) / 1000 },
            set: { settings.hoverDelayMilliseconds = Int(($0 * 1000).rounded()) }
        )
    }

    private func explanation(for permission: PermissionKind) -> String {
        switch permission {
        case .accessibility: "Pasting into other apps and media keys"
        case .inputMonitoring: "Optional typed shortcut detection"
        case .screenRecording: "Only for region text capture"
        case .notifications: "Timer alerts and reminders"
        case .screenshotFolder: "Optional screenshot folder monitoring"
        case .iCloud: "Optional user-owned synchronization"
        }
    }

    private func stateColor(_ state: PermissionState) -> Color {
        switch state {
        case .granted: .green
        case .denied: .orange
        case .notDetermined: .secondary
        case .unavailable: .red
        }
    }
}

/// Sidebar tile: a rounded square with a diagonal gradient of the pane tint, a hairline
/// light border and a soft tinted shadow, holding a white symbol.
struct SettingsTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 8 / 26, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: size * 8 / 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7)
                    .blendMode(.plusLighter)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 13 / 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.35), radius: 2, y: 1)
    }
}

/// Launch at login through the system login-item service. Unsigned development builds may be
/// refused by the system; the toggle then reverts and shows why.
private struct LaunchAtLoginToggle: View {
    /// Read once when the row appears: the status is a synchronous call into the system, too
    /// slow to repeat on every rebuild of the settings view.
    @State private var enabled = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Launch at login", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        errorText = nil
                    } catch {
                        errorText = error.localizedDescription
                    }
                    enabled = SMAppService.mainApp.status == .enabled
                }
            ))
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { enabled = SMAppService.mainApp.status == .enabled }
    }
}
