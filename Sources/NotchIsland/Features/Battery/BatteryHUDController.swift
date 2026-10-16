import AppKit
import Combine
import SwiftUI

/// One showing of a battery alert. A fresh `id` per showing re-creates the alert's views so
/// their pulse and MagSafe animations start over, as Atoll's per-alert token does.
struct BatteryHUDPresentation: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: BatteryHUDKind
    /// Level shown instead of the live one (test alerts).
    let levelOverride: Int?
    /// Low Power Mode shown instead of the live one (test alerts).
    let lowPowerModeOverride: Bool?
}

/// Turns delivered battery events into temporary alerts and hides them after their duration.
@MainActor
final class BatteryHUDController: ObservableObject {
    static let shared = BatteryHUDController()

    @Published private(set) var presentation: BatteryHUDPresentation?

    let monitor: BatteryMonitor
    let settings: BatterySettings
    /// Off in tests.
    var playsAlertSound = true

    private var deliverySubscription: AnyCancellable?
    private var hideTask: Task<Void, Never>?

    init(monitor: BatteryMonitor = .shared, settings: BatterySettings = .shared) {
        self.monitor = monitor
        self.settings = settings
    }

    func start() {
        guard deliverySubscription == nil else { return }
        deliverySubscription = monitor.deliveries.sink { [weak self] delivery in
            self?.handle(delivery)
        }
    }

    func stop() {
        deliverySubscription = nil
        hideTask?.cancel()
        hideTask = nil
        presentation = nil
    }

    /// The level the alert shows: the test override, else the live level.
    var displayedLevel: Int {
        min(max(presentation?.levelOverride ?? monitor.state.level, 0), 100)
    }

    var displayedLowPowerMode: Bool {
        presentation?.lowPowerModeOverride ?? monitor.state.isInLowPowerMode
    }

    func handle(_ delivery: BatteryDelivery) {
        guard delivery.after.hasBattery,
              let trigger = BatteryEventRules.trigger(
                for: delivery.event,
                before: delivery.before,
                lowThreshold: settings.lowBatteryThreshold,
                fullThreshold: settings.fullBatteryThreshold
              )
        else { return }
        present(trigger.kind)
        // Atoll chimes whenever the level crosses the threshold, even with the alert off.
        if trigger.playsAlertSound, settings.playLowBatteryAlertSound {
            playLowBatteryAlert()
        }
    }

    /// Shows `kind` unless notifications or that alert are switched off; `force` skips both
    /// checks (the Settings test buttons).
    func present(
        _ kind: BatteryHUDKind,
        force: Bool = false,
        levelOverride: Int? = nil,
        lowPowerModeOverride: Bool? = nil
    ) {
        guard force || settings.showPowerStatusNotifications else { return }
        guard force || settings.isHUDEnabled(kind) else { return }
        withAnimation(.smooth) {
            presentation = BatteryHUDPresentation(
                id: UUID(),
                kind: kind,
                levelOverride: levelOverride,
                lowPowerModeOverride: lowPowerModeOverride
            )
        }
        scheduleHide(after: .seconds(settings.duration(for: kind)))
    }

    /// Atoll's preview levels: the live level kept within 12...95 for charging, the low
    /// threshold capped to 5...20 for low, and 100 for full.
    func triggerTestHUD(_ kind: BatteryHUDKind) {
        let level: Int = switch kind {
        case .charging: max(12, min(95, monitor.state.level))
        case .lowBattery: max(5, min(20, settings.lowBatteryThreshold))
        case .fullBattery: 100
        }
        present(
            kind,
            force: true,
            levelOverride: level,
            lowPowerModeOverride: kind == .lowBattery ? monitor.state.isInLowPowerMode : nil
        )
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        guard presentation != nil else { return }
        withAnimation(.smooth) { presentation = nil }
    }

    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            withAnimation(.smooth) { self.presentation = nil }
        }
    }

    private func playLowBatteryAlert() {
        guard playsAlertSound else { return }
        // Atoll ships its own chime; a system alert sound stands in for it.
        NSSound(named: NSSound.Name("Funk"))?.play()
    }
}
