import ApplicationServices
import SwiftUI

struct FaceGeneralSettingsSection: View {
    @ObservedObject var preferences: FaceCheckPreferences
    @ObservedObject var unlock: MacUnlockController
    @ObservedObject var appSettings: UserSettings
    @ObservedObject var devices: FaceCheckDeviceCatalog
    var openPassword: () -> Void
    @State private var inputAccess = MacUnlockSpaceTrigger.hasAccess
    @State private var authorizationTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            LaunchAtLoginToggle()
            Toggle("Show in menu bar", isOn: $appSettings.showInMenuBar)
            Toggle("Enable Face Unlock", isOn: Binding(get: { unlock.isEnabled }, set: { enabled in
                if !enabled { unlock.disable() }
                else if !unlock.hasPassword { openPassword() }
                else { authorize() }
            }))
            .disabled(unlock.isBusy || (!unlock.isEnabled && unlock.setupUnavailableReason != nil))
            if let reason = unlock.setupUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            if unlock.hasPassword, !unlock.isAuthorized {
                Button("Authorize Face Unlock") { authorize() }
                    .disabled(unlock.isBusy || unlock.setupUnavailableReason != nil)
            }
            if !unlock.accessibilityGranted { FaceAccessibilityButton() }
        }
        .onDisappear {
            if authorizationTask != nil {
                authorizationTask?.cancel()
                authorizationTask = nil
                unlock.cancelSetup()
            }
        }
        Section("Triggers") {
            HStack(spacing: 8) {
                FaceOptionTile(title: "On wake", symbol: "moon.fill", selected: preferences.options.onWake) {
                    preferences.options.onWake.toggle()
                }
                FaceOptionTile(title: "On lock", symbol: "laptopcomputer", selected: preferences.options.onLock) {
                    preferences.options.onLock.toggle()
                }
                FaceOptionTile(title: "On space", symbol: "space", selected: preferences.options.onSpace) {
                    preferences.options.onSpace.toggle()
                    if preferences.options.onSpace { inputAccess = MacUnlockSpaceTrigger.requestAccess() }
                }
            }
            Text("Select when to check your face. On space listens for the spacebar only while your Mac is locked.")
                .font(.caption).foregroundStyle(.secondary)
            if preferences.options.onSpace, !inputAccess {
                Button("Allow Input Monitoring…") {
                    inputAccess = MacUnlockSpaceTrigger.requestAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
            if !preferences.options.onWake && !preferences.options.onLock && !preferences.options.onSpace {
                Text("Choose at least one trigger to start automatic checks.").font(.caption).foregroundStyle(.orange)
            }
            Picker("Display on", selection: $preferences.options.displayID) {
                Text("Main display").tag("main")
                Text("Built-in display").tag("builtin")
                ForEach(devices.displays) { Text($0.name).tag($0.id) }
                if !["main", "builtin"].contains(preferences.options.displayID),
                   !devices.displays.contains(where: { $0.id == preferences.options.displayID }) {
                    Text("Disconnected display (using main)").tag(preferences.options.displayID)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { inputAccess = MacUnlockSpaceTrigger.hasAccess } }
        Section("Behaviour") {
            Toggle("Retry on notch hover", isOn: $preferences.options.retryOnHover)
                .disabled(!preferences.options.showAnimation)
            Toggle("Auto retry once after failure", isOn: $preferences.options.autoRetry)
            Toggle("Haptic feedback", isOn: $preferences.options.haptics)
            VStack(alignment: .leading) {
                HStack { Text("Face detection duration"); Spacer(); Text("\(Int(preferences.options.scanDuration)) s").foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $preferences.options.detectionDuration, in: 3...30, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Face detection duration in seconds")
            }
        }
        Section("Animation") {
            Toggle("Show animation", isOn: $preferences.options.showAnimation)
            HStack(spacing: 12) {
                ForEach(FaceUnlockAnimationStyle.allCases) { style in
                    Button { preferences.options.animationStyle = style } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: style == .minimal ? 24 : 20).fill(.black)
                                    .frame(width: style == .minimal ? 140 : 80, height: style == .minimal ? 42 : 80)
                                HStack {
                                    if style == .minimal { Image(systemName: "lock.fill").foregroundStyle(.white); Spacer().frame(width: 55) }
                                    Image(systemName: "faceid").font(.system(size: style == .minimal ? 22 : 36)).foregroundStyle(.blue)
                                }
                            }.frame(height: 86)
                            Text(style.title).fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(preferences.options.animationStyle == style ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.options.animationStyle == style ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preferences.options.animationStyle == style ? .isSelected : [])
                }
            }
            .disabled(!preferences.options.showAnimation)
        }
        if case .failed(let message) = unlock.state { Section { Text(message).foregroundStyle(.orange) } }
    }

    private func authorize() {
        guard authorizationTask == nil, !unlock.isBusy else { return }
        authorizationTask = Task {
            guard !Task.isCancelled else { return }
            await unlock.authorizeSession()
            guard !Task.isCancelled else { return }
            authorizationTask = nil
        }
    }
}

struct FaceOptionTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2).frame(height: 28)
                Text(title).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FaceAccessibilityButton: View {
    var body: some View {
        Button("Allow Accessibility…") {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
