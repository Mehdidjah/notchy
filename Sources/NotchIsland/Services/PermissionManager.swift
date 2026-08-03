import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import UserNotifications

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case notifications
    case screenshotFolder
    case iCloud

    var id: Self { self }

    var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        case .notifications: "Notifications"
        case .screenshotFolder: "Screenshot Folders"
        case .iCloud: "iCloud"
        }
    }
}

enum PermissionState: String, Sendable {
    case notDetermined
    case denied
    case granted
    case unavailable
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]

    init() {
        refresh()
    }

    func refresh() {
        states[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        states[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .denied
        states[.inputMonitoring] = .notDetermined
        states[.screenshotFolder] = .notDetermined
        states[.iCloud] = .unavailable
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self.states[.notifications] = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            case .notDetermined: .notDetermined
            @unknown default: .unavailable
            }
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            self.refresh()
        }
    }

    func openSystemSettings(for kind: PermissionKind) {
        let path: String = switch kind {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications:
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .screenshotFolder:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .iCloud:
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane"
        }
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }
}
