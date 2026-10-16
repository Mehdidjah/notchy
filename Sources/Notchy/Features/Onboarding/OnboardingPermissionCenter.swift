import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreServices
import EventKit
import SwiftUI

/// Permissions the onboarding walks through.
enum OnboardingPermission: String, CaseIterable, Identifiable, Sendable {
    /// Pasting into other apps and listening for media and brightness keys.
    case accessibility
    /// The camera mirror on the Home tab.
    case camera
    /// Calendar events on the Home tab and the reminder live activity.
    case calendar
    /// Apple Events to the Music app for now-playing info and controls.
    case automationMusic
    /// Apple Events to Spotify for now-playing info and controls.
    case automationSpotify

    var id: String { rawValue }

    /// System Settings pane that lists this permission.
    var settingsURL: URL? {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .camera: "Privacy_Camera"
        case .calendar: "Privacy_Calendars"
        case .automationMusic, .automationSpotify: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// Bundle identifier of the app an Automation permission targets.
    var automationTarget: String? {
        switch self {
        case .automationMusic: "com.apple.Music"
        case .automationSpotify: "com.spotify.client"
        case .accessibility, .camera, .calendar: nil
        }
    }

    /// Name of the app an Automation permission targets.
    var automationTargetName: String? {
        switch self {
        case .automationMusic: "Music"
        case .automationSpotify: "Spotify"
        case .accessibility, .camera, .calendar: nil
        }
    }
}

enum OnboardingPermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
    /// Automation can only be asked for while the target app is running.
    case targetNotRunning
    case targetNotInstalled

    var isGranted: Bool { self == .granted }

    /// The system prompt can still be shown (or, for Automation, shown after a launch).
    var canPrompt: Bool { self == .notDetermined || self == .targetNotRunning }

    var label: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested yet"
        case .restricted: "Restricted on this Mac"
        case .targetNotRunning: "Asks when the app opens"
        case .targetNotInstalled: "App not installed"
        }
    }

    /// A shorter label for tight spaces such as the music cards.
    var shortLabel: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not asked"
        case .restricted: "Restricted"
        case .targetNotRunning: "Asks on launch"
        case .targetNotInstalled: "Not installed"
        }
    }

    var tint: Color {
        switch self {
        case .granted: .green
        case .denied: .orange
        case .restricted: .red
        case .notDetermined, .targetNotRunning, .targetNotInstalled: .secondary
        }
    }

    // MARK: Mapping from system values

    static func camera(_ status: AVAuthorizationStatus) -> OnboardingPermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    static func calendar(_ status: EKAuthorizationStatus) -> OnboardingPermissionStatus {
        switch status {
        case .fullAccess: .granted
        // Write-only access cannot read events, so the calendar still needs full access.
        case .writeOnly, .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Codes returned by `AEDeterminePermissionToAutomateTarget`.
    enum AutomationCode {
        static let allowed: OSStatus = 0
        static let notPermitted: OSStatus = -1743
        static let wouldRequireConsent: OSStatus = -1744
        static let processNotFound: OSStatus = -600
    }

    static func automation(_ code: OSStatus) -> OnboardingPermissionStatus {
        switch code {
        case AutomationCode.allowed: .granted
        case AutomationCode.notPermitted: .denied
        case AutomationCode.wouldRequireConsent: .notDetermined
        case AutomationCode.processNotFound: .targetNotRunning
        default: .notDetermined
        }
    }

    static func accessibility(trusted: Bool, requested: Bool) -> OnboardingPermissionStatus {
        if trusted { return .granted }
        return requested ? .denied : .notDetermined
    }
}

/// Live permission status for the onboarding pages. While monitoring it re-reads every
/// status once a second (Accessibility has no change notification) and whenever the app
/// becomes active again, for example after returning from System Settings.
@MainActor
final class OnboardingPermissionCenter: ObservableObject {
    static let shared = OnboardingPermissionCenter()

    @Published private(set) var statuses: [OnboardingPermission: OnboardingPermissionStatus] = [:]
    @Published private(set) var requestsInFlight: Set<OnboardingPermission> = []

    private var monitorTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var automationRefreshInFlight = false
    private var accessibilityRequested = false
    private var tick = 0

    init() {
        refreshLocalStatuses()
    }

    func status(of permission: OnboardingPermission) -> OnboardingPermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    // MARK: Monitoring

    func startMonitoring() {
        guard monitorTask == nil else { return }
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick += 1
                self.refreshLocalStatuses()
                if self.tick % 2 == 0 { self.refreshAutomationStatuses() }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func refresh() {
        refreshLocalStatuses()
        refreshAutomationStatuses()
    }

    /// Statuses that are cheap to read on the main thread.
    private func refreshLocalStatuses() {
        update(.accessibility, to: .accessibility(trusted: AXIsProcessTrusted(), requested: accessibilityRequested))
        update(.camera, to: .camera(AVCaptureDevice.authorizationStatus(for: .video)))
        update(.calendar, to: .calendar(EKEventStore.authorizationStatus(for: .event)))
    }

    /// Automation checks talk to the target app, so they run off the main thread.
    private func refreshAutomationStatuses() {
        guard !automationRefreshInFlight else { return }
        let targets: [(OnboardingPermission, String)] = [OnboardingPermission.automationMusic, .automationSpotify]
            .compactMap { permission in permission.automationTarget.map { (permission, $0) } }
        var pending: [(OnboardingPermission, String)] = []
        for (permission, bundleID) in targets where !requestsInFlight.contains(permission) {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil {
                update(permission, to: .targetNotInstalled)
            } else if !Self.isRunning(bundleID) {
                // Keep a known answer; otherwise the system can only ask once the app runs.
                let current = status(of: permission)
                if current != .granted && current != .denied { update(permission, to: .targetNotRunning) }
            } else {
                pending.append((permission, bundleID))
            }
        }
        guard !pending.isEmpty else { return }
        automationRefreshInFlight = true
        let bundleIDs = pending.map(\.1)
        Task { @MainActor [weak self] in
            let codes = await Task.detached(priority: .utility) {
                bundleIDs.map { Self.automationCode(bundleIdentifier: $0, askUserIfNeeded: false) }
            }.value
            guard let self else { return }
            self.automationRefreshInFlight = false
            for (index, entry) in pending.enumerated() where !self.requestsInFlight.contains(entry.0) {
                self.update(entry.0, to: .automation(codes[index]))
            }
        }
    }

    private func update(_ permission: OnboardingPermission, to status: OnboardingPermissionStatus) {
        if statuses[permission] != status { statuses[permission] = status }
    }

    // MARK: Requests

    /// Shows the system prompt for a permission, or opens System Settings when the system
    /// will no longer ask.
    func request(_ permission: OnboardingPermission) async {
        guard !requestsInFlight.contains(permission) else { return }
        let current = status(of: permission)
        if current == .denied || current == .restricted {
            openSystemSettings(for: permission)
            return
        }
        requestsInFlight.insert(permission)
        defer { requestsInFlight.remove(permission) }

        switch permission {
        case .accessibility:
            accessibilityRequested = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                openSystemSettings(for: .accessibility)
            }
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .calendar:
            _ = await Self.requestCalendarAccess()
        case .automationMusic, .automationSpotify:
            guard let bundleID = permission.automationTarget else { break }
            await requestAutomation(permission, bundleID: bundleID)
        }
        refreshLocalStatuses()
    }

    private func requestAutomation(_ permission: OnboardingPermission, bundleID: String) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            update(permission, to: .targetNotInstalled)
            return
        }
        if !Self.isRunning(bundleID) {
            // The consent prompt needs a running target: start it quietly in the background.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
            for _ in 0..<40 where !Self.isRunning(bundleID) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Give the app a moment to install its Apple Event handlers.
            try? await Task.sleep(for: .milliseconds(600))
        }
        let code = await Task.detached(priority: .userInitiated) {
            Self.automationCode(bundleIdentifier: bundleID, askUserIfNeeded: true)
        }.value
        update(permission, to: .automation(code))
    }

    func openSystemSettings(for permission: OnboardingPermission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: System calls

    nonisolated static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Asks the Apple Event manager whether this app may send events to `bundleIdentifier`.
    /// Blocks while the consent prompt is up, so never call it on the main thread.
    nonisolated static func automationCode(bundleIdentifier: String, askUserIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let address = target.aeDesc else { return OnboardingPermissionStatus.AutomationCode.processNotFound }
        return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askUserIfNeeded)
    }

    nonisolated static func requestCalendarAccess() async -> Bool {
        let store = EKEventStore()
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }
}
