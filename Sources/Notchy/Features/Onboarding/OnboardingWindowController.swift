import AppKit
import SwiftUI

/// Presents the onboarding window: 400 x 600, titled with a transparent title bar and full-size
/// content, no title text, centred, not restorable. While it is up the app becomes a regular
/// app (Dock icon, menu bar) so the window can take focus; finishing returns it to an
/// accessory app (Atoll's showOnboardingWindow).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    static let windowIdentifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

    private(set) var window: NSWindow?
    private var flow: OnboardingFlowModel?
    private let settings: OnboardingSettings
    private let permissions: OnboardingPermissionCenter

    init(settings: OnboardingSettings = .shared, permissions: OnboardingPermissionCenter = .shared) {
        self.settings = settings
        self.permissions = permissions
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Shows the onboarding when it has not been completed yet.
    static func showIfNeeded() {
        guard OnboardingSettings.shared.needsOnboarding else { return }
        shared.show()
    }

    /// Shows the onboarding window, starting from the welcome page unless it is already open.
    func show() {
        if window == nil || !isVisible {
            buildWindow()
        }
        guard let window else { return }
        permissions.startMonitoring()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Closes the window without marking the onboarding complete.
    func dismiss() {
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        restoreAccessoryPolicy()
    }

    private func buildWindow() {
        let flow = OnboardingFlowModel(
            selectedProfiles: settings.selectedProfiles,
            musicSource: OnboardingFeature.currentMusicSource?() ?? settings.musicSource,
            baseChoices: OnboardingFeature.currentFeatureChoices?() ?? .atollDefaults
        )
        self.flow = flow

        let root = OnboardingView(
            flow: flow,
            permissions: permissions,
            onMusicSourceChosen: { [weak self] source in self?.saveMusicSource(source) },
            onFeaturesChosen: { [weak self] profiles, choices in self?.saveFeatures(profiles: profiles, choices: choices) },
            onFinish: { [weak self] in self?.complete(openingSettings: false) },
            onOpenSettings: { [weak self] in self?.complete(openingSettings: true) },
            // Atoll asks only during the first-run onboarding, not when it is shown again.
            onFocusDetectionModeChosen: settings.completed ? nil : OnboardingFeature.applyFocusDetectionMode
        )

        let window = self.window ?? NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.windowSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Onboarding"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.identifier = Self.windowIdentifier
        window.delegate = self
        if UserDefaults.standard.bool(forKey: "notch.hideFromScreenCapture") {
            window.sharingType = .none
        }
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: OnboardingView.windowSize)
        window.contentView = hostingView
        window.setContentSize(OnboardingView.windowSize)
        window.center()
        self.window = window
    }

    private func saveMusicSource(_ source: OnboardingMusicSource) {
        settings.musicSource = source
        OnboardingFeature.applyMusicSource?(source)
        NotificationCenter.default.post(name: .onboardingMusicSourceChanged, object: source.rawValue)
    }

    private func saveFeatures(profiles: Set<OnboardingProfile>, choices: OnboardingFeatureChoices) {
        settings.selectedProfiles = profiles
        OnboardingFeature.applyFeatureChoices?(choices)
    }

    private func complete(openingSettings: Bool) {
        settings.markCompleted()
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        restoreAccessoryPolicy()
        if openingSettings {
            OnboardingFeature.openSettings?()
        } else {
            NSApp.deactivate()
        }
    }

    private func restoreAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopMonitoring()
        flow = nil
    }
}
