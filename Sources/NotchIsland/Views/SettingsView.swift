import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var settings: UserSettings
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gear") }
            capture
                .tabItem { Label("Capture", systemImage: "doc.on.clipboard") }
            notch
                .tabItem { Label("Notch", systemImage: "macbook") }
            history
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            permissionSettings
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(16)
        .frame(width: 620, height: 440)
    }

    private var general: some View {
        Form {
            Section("Behavior") {
                Picker("Default card action", selection: $settings.defaultAction) {
                    Text("Paste immediately").tag(DefaultClipAction.paste)
                    Text("Copy only").tag(DefaultClipAction.copy)
                    Text("Preview").tag(DefaultClipAction.preview)
                }
                Toggle("Show menu bar icon", isOn: .constant(true))
                    .disabled(true)
                LabeledContent("Quick Paste shortcut", value: "Control + Command + V")
                LabeledContent("Sequential paste", value: "Command + Down Arrow")
            }
            Section("Distribution") {
                Text("This build is a local accessory app. Developer ID signing, notarization, Sparkle feed settings, and DMG release credentials are configured during distribution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var capture: some View {
        Form {
            Section("Clipboard Capture") {
                Toggle("Save clipboard history", isOn: $settings.captureEnabled)
                Toggle("Manual capture only", isOn: $settings.manualCaptureOnly)
                Stepper(
                    "Maximum payload: \(settings.maxPayloadMegabytes) MB",
                    value: $settings.maxPayloadMegabytes,
                    in: 1...500,
                    step: 5
                )
                Picker("Duplicate copies", selection: $settings.duplicateBehavior) {
                    Text("Move original to front").tag(DuplicateCaptureBehavior.moveOriginalToFront)
                    Text("Store every event").tag(DuplicateCaptureBehavior.storeSeparateEvent)
                }
            }
            Section {
                Text("Ignored applications and content types are stored locally in preferences. Clipboard capture never uploads content to a NotchIsland server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var notch: some View {
        Form {
            Section("Hover Shelf") {
                Toggle("Enable notch shelf", isOn: $settings.notchEnabled)
                    .onChange(of: settings.notchEnabled) { _, enabled in
                        model.setNotchEnabled(enabled)
                    }
                Stepper(
                    "Hover dwell: \(settings.hoverDelayMilliseconds) ms",
                    value: $settings.hoverDelayMilliseconds,
                    in: 100...1000,
                    step: 50
                )
                Stepper(
                    "Close delay: \(settings.closeDelayMilliseconds) ms",
                    value: $settings.closeDelayMilliseconds,
                    in: 100...1000,
                    step: 50
                )
                LabeledContent("Shelf width") {
                    HStack {
                        Slider(value: $settings.expandedWidth, in: 680...920, step: 10)
                        Text("\(Int(settings.expandedWidth)) pt").monospacedDigit().frame(width: 62)
                    }
                }
                Toggle("Hide in fullscreen", isOn: $settings.hideInFullscreen)
            }
        }
        .formStyle(.grouped)
    }

    private var history: some View {
        Form {
            Section("Retention") {
                Picker("Delete unprotected clips after", selection: $settings.retentionPreset) {
                    Text("7 days").tag(RetentionPreset.sevenDays)
                    Text("15 days").tag(RetentionPreset.fifteenDays)
                    Text("30 days").tag(RetentionPreset.thirtyDays)
                    Text("90 days").tag(RetentionPreset.ninetyDays)
                    Text("Never").tag(RetentionPreset.forever)
                }
                Stepper(
                    "Maximum items: \(settings.maximumItemCount.formatted())",
                    value: $settings.maximumItemCount,
                    in: 100...100_000,
                    step: 100
                )
                Text("Favorites, pinned clips, and manually saved clips are preserved by cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Clear non-protected history", role: .destructive) {
                    model.clearHistoryPreservingProtected()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("Sensitive Content") {
                Toggle("Allow manually saved sensitive clips", isOn: $settings.saveSensitiveContent)
                Text("Password-like values, API keys, tokens, private keys, payment-card numbers, .env secrets, and credentialed database URLs are skipped locally by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Cloud and Integrations") {
                Toggle("iCloud Sync", isOn: .constant(false)).disabled(true)
                Toggle("Dropbox", isOn: .constant(false)).disabled(true)
                Text("Cloud and Dropbox remain disabled until the required entitlements and OAuth credentials are supplied. Core clipboard history is fully local and offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var permissionSettings: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { permission in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.displayName)
                            Text(explanation(for: permission))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                Text("Accessibility is optional: without it, selecting a clip copies it and shows copy-only feedback instead of sending Command-V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func explanation(for permission: PermissionKind) -> String {
        switch permission {
        case .accessibility: "Automatic paste and inline expansion"
        case .inputMonitoring: "Optional typed shortcut detection"
        case .screenRecording: "Only for region text capture"
        case .notifications: "Clip reminders and private skip notices"
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
