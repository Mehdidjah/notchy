import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

/// The two power assertions Keep Awake can hold.
enum CaffeinateAssertionKind: Sendable, Equatable, CaseIterable {
    /// Stops idle system sleep; the screen may still dim and sleep.
    case preventSystemSleep
    /// Also keeps the display on, like `caffeinate -d`.
    case preventDisplaySleep

    var assertionType: CFString {
        switch self {
        case .preventSystemSleep: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .preventDisplaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }
    }
}

/// Creates and releases power assertions. The live implementation calls IOKit; tests use a fake.
@MainActor
protocol CaffeinatePowerAssertions: AnyObject {
    /// Returns the new assertion's ID, or nil when IOKit refused it.
    func create(_ kind: CaffeinateAssertionKind, reason: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

/// Public IOKit power management (`IOPMAssertionCreateWithName`), the mechanism behind
/// `caffeinate(8)`. Assertions belong to this process, so macOS drops them if the app exits.
@MainActor
final class IOKitCaffeinateAssertions: CaffeinatePowerAssertions {
    func create(_ kind: CaffeinateAssertionKind, reason: String) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }
}

/// Keeps the Mac awake for a chosen time by holding a power assertion, with a once-a-second
/// countdown for timed sessions. Starting a new duration replaces the running session rather
/// than stacking a second one. Everything is released on `deactivate()`, when the feature is
/// switched off, and when the app quits.
@MainActor
final class CaffeinateController: ObservableObject {
    static let shared = CaffeinateController()

    static let assertionReason = "NotchIsland is keeping this Mac awake"

    @Published private(set) var isActive = false
    /// When the running session ends, or nil for an indefinite one.
    @Published private(set) var expiresAt: Date?
    /// Seconds left in a timed session, refreshed every second; nil when idle or indefinite.
    @Published private(set) var remainingTime: TimeInterval?
    /// The duration the running session was started with.
    @Published private(set) var activeDuration: CaffeinateDuration?
    /// Whether the header popover is showing; the island should stay open meanwhile.
    @Published private(set) var isPopoverPresented = false

    /// Told when the popover opens or closes, so the island can hold itself open while it is up
    /// and re-check the pointer after it closes.
    var onPopoverPresentationChanged: ((Bool) -> Void)?

    let settings: CaffeinateSettings
    private let assertions: any CaffeinatePowerAssertions
    private let now: () -> Date
    private var systemAssertionID: IOPMAssertionID?
    private var displayAssertionID: IOPMAssertionID?
    private var ticker: Task<Void, Never>?
    private var settingsSubscriptions: Set<AnyCancellable> = []
    private var terminationObserver: (any NSObjectProtocol)?

    init(
        settings: CaffeinateSettings = .shared,
        assertions: any CaffeinatePowerAssertions = IOKitCaffeinateAssertions(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.assertions = assertions
        self.now = now
    }

    /// Held assertion IDs, for diagnostics and tests.
    var heldAssertionIDs: [IOPMAssertionID] {
        [systemAssertionID, displayAssertionID].compactMap(\.self)
    }

    // MARK: Lifecycle

    /// Follows the settings (switching the feature off ends the session; the display option
    /// applies to a running session at once) and releases everything when the app quits.
    func startObserving() {
        guard settingsSubscriptions.isEmpty else { return }
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard !enabled else { return }
                self?.deactivate()
                self?.setPopoverPresented(false)
            }
            .store(in: &settingsSubscriptions)
        settings.$keepsDisplayAwake
            .removeDuplicates()
            .sink { [weak self] keepsDisplayAwake in
                self?.syncDisplayAssertion(keepsDisplayAwake: keepsDisplayAwake)
            }
            .store(in: &settingsSubscriptions)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deactivate() }
        }
    }

    func stopObserving() {
        settingsSubscriptions.removeAll()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
    }

    // MARK: Control

    /// Starts a session of `duration`, replacing any session already running.
    func activate(for duration: CaffeinateDuration) {
        deactivate()
        guard settings.isEnabled else { return }
        guard let systemID = assertions.create(.preventSystemSleep, reason: Self.assertionReason) else {
            return
        }
        systemAssertionID = systemID
        if settings.keepsDisplayAwake {
            displayAssertionID = assertions.create(.preventDisplaySleep, reason: Self.assertionReason)
        }
        let start = now()
        isActive = true
        activeDuration = duration
        expiresAt = duration.expiry(from: start)
        remainingTime = expiresAt.map { max(0, $0.timeIntervalSince(start)) }
        startTicking()
    }

    /// Releases every assertion. Safe to call while idle.
    func deactivate() {
        ticker?.cancel()
        ticker = nil
        for id in heldAssertionIDs { assertions.release(id) }
        systemAssertionID = nil
        displayAssertionID = nil
        if isActive { isActive = false }
        if expiresAt != nil { expiresAt = nil }
        if remainingTime != nil { remainingTime = nil }
        if activeDuration != nil { activeDuration = nil }
    }

    /// Starts the default duration, or ends the running session.
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: settings.defaultDuration)
        }
    }

    func setPopoverPresented(_ presented: Bool) {
        guard presented != isPopoverPresented else { return }
        isPopoverPresented = presented
        onPopoverPresentationChanged?(presented)
    }

    /// Text under the popover title: "Off", "12:34 left" or "On until turned off".
    var statusText: String {
        guard isActive else { return "Off" }
        if let remainingTime {
            return "\(CaffeinateDuration.remainingLabel(remainingTime)) left"
        }
        return "On until turned off"
    }

    // MARK: Countdown

    /// Re-reads the clock: refreshes the countdown and ends the session once it runs out.
    func tick() {
        guard isActive, let expiresAt else { return }
        let left = max(0, expiresAt.timeIntervalSince(now()))
        remainingTime = left
        if left <= 0 { deactivate() }
    }

    private func startTicking() {
        ticker?.cancel()
        guard expiresAt != nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func syncDisplayAssertion(keepsDisplayAwake: Bool) {
        guard isActive else { return }
        if keepsDisplayAwake, displayAssertionID == nil {
            displayAssertionID = assertions.create(.preventDisplaySleep, reason: Self.assertionReason)
        } else if !keepsDisplayAwake, let id = displayAssertionID {
            assertions.release(id)
            displayAssertionID = nil
        }
    }
}
