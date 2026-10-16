import Foundation
import IOKit.ps
import SwiftUI
import Testing
@testable import Notchy

@MainActor
struct BatteryTests {
    // MARK: Helpers

    private func snapshot(
        level: Int = 50,
        pluggedIn: Bool = false,
        charging: Bool = false,
        lowPower: Bool = false
    ) -> BatterySnapshot {
        BatterySnapshot(
            hasBattery: true,
            level: level,
            maxCapacity: 100,
            isPluggedIn: pluggedIn,
            isCharging: charging,
            isInLowPowerMode: lowPower,
            timeToFullCharge: 0,
            timeToEmpty: 0
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "BatteryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func context(hovering: Bool = false) -> ClosedActivityContext {
        ClosedActivityContext(
            closedHeight: 32,
            notchWidth: 185,
            isHovering: hovering,
            gestureProgress: 0,
            hasHardwareNotch: true
        )
    }

    // MARK: IOKit parsing

    @Test
    func parsesAPowerSourceDescription() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 76,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSTimeToFullChargeKey: 42,
            kIOPSTimeToEmptyKey: -1,
            kIOPSIsPresentKey: true
        ]
        let parsed = BatterySnapshot.snapshot(from: description, lowPowerMode: true)
        #expect(parsed.hasBattery)
        #expect(parsed.level == 76)
        #expect(parsed.isPluggedIn)
        #expect(parsed.isCharging)
        #expect(parsed.isInLowPowerMode)
        #expect(parsed.timeToFullCharge == 42)
        #expect(parsed.timeToEmpty == 0, "IOKit's -1 (still estimating) reads as unknown")
    }

    @Test
    func batteryPowerAndRawCapacityUnits() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 2_500,
            kIOPSMaxCapacityKey: 5_000,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue
        ]
        let parsed = BatterySnapshot.snapshot(from: description, lowPowerMode: false)
        #expect(parsed.level == 50)
        #expect(!parsed.isPluggedIn)
        #expect(!parsed.isCharging)
    }

    @Test
    func liveReadingIsWellFormed() async {
        let reading = await Task.detached { BatterySnapshot.read() }.value
        #expect((0...100).contains(reading.level))
        #expect(reading.timeToFullCharge >= 0)
        #expect(reading.isInLowPowerMode == ProcessInfo.processInfo.isLowPowerModeEnabled)
        if !reading.hasBattery {
            #expect(reading.level == 0)
        }
    }

    @Test
    func prefersTheInternalBatteryOverOtherSources() {
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 10, kIOPSMaxCapacityKey: 100]
        let builtIn: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 90, kIOPSMaxCapacityKey: 100]
        #expect(BatterySnapshot.snapshot(fromSources: [ups, builtIn], lowPowerMode: false).level == 90)
        #expect(BatterySnapshot.snapshot(fromSources: [ups], lowPowerMode: false).level == 10)
        #expect(!BatterySnapshot.snapshot(fromSources: [], lowPowerMode: false).hasBattery)
    }

    // MARK: Events and triggers

    @Test
    func eventsFollowAtollsOrder() {
        let old = snapshot(level: 50, pluggedIn: false, charging: false, lowPower: false)
        var new = snapshot(level: 51, pluggedIn: true, charging: true, lowPower: true)
        new.timeToFullCharge = 30
        let events = BatteryEventRules.events(from: old, to: new)
        #expect(events == [
            .powerSourceChanged(isPluggedIn: true),
            .levelChanged(51),
            .chargingChanged(true),
            .lowPowerModeChanged(true),
            .timeToFullChargeChanged(30)
        ])
        #expect(BatteryEventRules.events(from: old, to: old).isEmpty)
        let applied = events.reduce(old) { $0.applying($1) }
        #expect(applied == new)
    }

    @Test
    func pluggingInRaisesTheChargingAlert() {
        let unplugged = snapshot(pluggedIn: false)
        let trigger = BatteryEventRules.trigger(
            for: .powerSourceChanged(isPluggedIn: true), before: unplugged, lowThreshold: 20, fullThreshold: 100
        )
        #expect(trigger == BatteryHUDTrigger(kind: .charging, playsAlertSound: false))
        #expect(BatteryEventRules.trigger(
            for: .powerSourceChanged(isPluggedIn: false), before: snapshot(pluggedIn: true), lowThreshold: 20, fullThreshold: 100
        ) == nil, "unplugging raises nothing")
    }

    @Test
    func fallingAcrossTheLowThresholdOnBatteryChimes() {
        let rule = { (before: BatterySnapshot, level: Int) in
            BatteryEventRules.trigger(for: .levelChanged(level), before: before, lowThreshold: 20, fullThreshold: 100)
        }
        #expect(rule(snapshot(level: 21), 20) == BatteryHUDTrigger(kind: .lowBattery, playsAlertSound: true))
        #expect(rule(snapshot(level: 25), 18) == BatteryHUDTrigger(kind: .lowBattery, playsAlertSound: true))
        #expect(rule(snapshot(level: 20), 19) == nil, "already under the threshold")
        #expect(rule(snapshot(level: 21, pluggedIn: true), 20) == nil, "on power")
        #expect(rule(snapshot(level: 21, charging: true), 20) == nil, "charging")
        #expect(rule(snapshot(level: 22), 21) == nil, "still above")
    }

    @Test
    func risingToTheFullThresholdRaisesTheFullAlert() {
        let rule = { (before: BatterySnapshot, level: Int, full: Int) in
            BatteryEventRules.trigger(for: .levelChanged(level), before: before, lowThreshold: 20, fullThreshold: full)
        }
        #expect(rule(snapshot(level: 99, pluggedIn: true, charging: true), 100, 100)?.kind == .fullBattery)
        #expect(rule(snapshot(level: 79, pluggedIn: true), 80, 80)?.kind == .fullBattery)
        #expect(rule(snapshot(level: 100, pluggedIn: true), 100, 100) == nil)
        #expect(rule(snapshot(level: 100), 99, 100) == nil, "falling never raises full")
    }

    @Test
    func turningOnLowPowerModeRaisesTheLowAlertQuietly() {
        let trigger = BatteryEventRules.trigger(
            for: .lowPowerModeChanged(true), before: snapshot(level: 80), lowThreshold: 20, fullThreshold: 100
        )
        #expect(trigger == BatteryHUDTrigger(kind: .lowBattery, playsAlertSound: false))
        #expect(BatteryEventRules.trigger(
            for: .lowPowerModeChanged(false), before: snapshot(lowPower: true), lowThreshold: 20, fullThreshold: 100
        ) == nil)
    }

    // MARK: Metrics

    @Test
    func alertSizesMatchAtoll() {
        #expect(BatteryHUDMetrics.resolve(kind: .charging, style: .standard)
            == BatteryHUDMetrics(wingWidth: 90, bandHeight: 0, bottomCornerRadius: nil))
        #expect(BatteryHUDMetrics.resolve(kind: .lowBattery, style: .compact).wingWidth == 90)
        #expect(BatteryHUDMetrics.resolve(kind: .lowBattery, style: .standard)
            == BatteryHUDMetrics(wingWidth: 75, bandHeight: 75, bottomCornerRadius: 40))
        #expect(BatteryHUDMetrics.resolve(kind: .fullBattery, style: .standard)
            == BatteryHUDMetrics(wingWidth: 70, bandHeight: 70, bottomCornerRadius: 36))
    }

    @Test
    func glyphColoursAndFill() {
        #expect(BatteryGlyph.color(level: 50, isPluggedIn: false, isCharging: false, isInLowPowerMode: true) == .yellow)
        #expect(BatteryGlyph.color(level: 20, isPluggedIn: false, isCharging: false, isInLowPowerMode: false) == .red)
        #expect(BatteryGlyph.color(level: 20, isPluggedIn: true, isCharging: false, isInLowPowerMode: false) == .green)
        #expect(BatteryGlyph.color(level: 100, isPluggedIn: false, isCharging: false, isInLowPowerMode: false) == .green)
        #expect(BatteryGlyph.color(level: 60, isPluggedIn: false, isCharging: false, isInLowPowerMode: false) == .white)
        #expect(BatteryGlyph.fillWidth(level: 0, width: 30, inset: 1.5) == 0)
        #expect(BatteryGlyph.fillWidth(level: 1, width: 30, inset: 1.5) == 2, "a sliver never vanishes")
        #expect(BatteryGlyph.fillWidth(level: 50, width: 30, inset: 1.5) == 13.5)
        #expect(BatteryGlyph.fillWidth(level: 100, width: 30, inset: 1.5) == 27)
    }

    @Test
    func alertTints() {
        #expect(BatteryHUDTint.color(kind: .charging, level: 15, isLowPowerMode: false) == .red)
        #expect(BatteryHUDTint.color(kind: .charging, level: 60, isLowPowerMode: false) == .green)
        #expect(BatteryHUDTint.color(kind: .lowBattery, level: 60, isLowPowerMode: true) == .yellow)
        #expect(BatteryHUDTint.color(kind: .fullBattery, level: 100, isLowPowerMode: false) == .green)
    }

    // MARK: Settings

    @Test
    func settingsUseAtollDefaultsAndPersist() {
        let defaults = makeDefaults()
        let settings = BatterySettings(defaults: defaults)
        #expect(settings.showBatteryIndicator)
        #expect(settings.showBatteryPercentInside)
        #expect(settings.showPowerStatusNotifications)
        #expect(settings.lowBatteryThreshold == 20)
        #expect(settings.fullBatteryThreshold == 100)
        #expect(settings.duration(for: .charging) == 3)
        #expect(settings.style(for: .charging) == .compact)
        #expect(settings.style(for: .lowBattery) == .standard)

        settings.lowBatteryThreshold = 15
        settings.fullBatteryHUDStyle = .compact
        settings.showChargingHUD = false
        let reloaded = BatterySettings(defaults: defaults)
        #expect(reloaded.lowBatteryThreshold == 15)
        #expect(reloaded.fullBatteryHUDStyle == .compact)
        #expect(!reloaded.isHUDEnabled(.charging))

        defaults.set(99, forKey: BatterySettings.Key.lowBatteryThreshold)
        defaults.set(0, forKey: BatterySettings.Key.chargingHUDDuration)
        let clamped = BatterySettings(defaults: defaults)
        #expect(clamped.lowBatteryThreshold == 30)
        #expect(clamped.duration(for: .charging) == 1)
    }

    // MARK: Monitor, controller, activity

    @Test
    func monitorTakesTheFirstReadingSilentlyThenDeliversChanges() async throws {
        let monitor = BatteryMonitor(eventSpacing: .zero, reader: { .unavailable })
        var delivered: [BatteryEvent] = []
        let subscription = monitor.deliveries.sink { delivered.append($0.event) }
        defer { subscription.cancel() }

        monitor.ingest(snapshot(level: 50))
        #expect(monitor.hasLoaded)
        #expect(monitor.state.level == 50)

        monitor.ingest(snapshot(level: 51, pluggedIn: true))
        for _ in 0..<50 where delivered.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(delivered == [.powerSourceChanged(isPluggedIn: true), .levelChanged(51)])
        #expect(monitor.state.isPluggedIn)
        #expect(monitor.state.level == 51)
    }

    @Test
    func timeRemainingUpdatesWithoutQueuingAnEvent() async throws {
        let monitor = BatteryMonitor(eventSpacing: .zero, reader: { .unavailable })
        var delivered = 0
        let subscription = monitor.deliveries.sink { _ in delivered += 1 }
        defer { subscription.cancel() }
        monitor.ingest(snapshot(level: 50))
        var later = snapshot(level: 50)
        later.timeToEmpty = 245
        monitor.ingest(later)
        #expect(monitor.state.timeToEmpty == 245)
        try await Task.sleep(for: .milliseconds(30))
        #expect(delivered == 0)
    }

    @Test
    func controllerPresentsFromDeliveriesAndHonoursSwitches() {
        let settings = BatterySettings(defaults: makeDefaults())
        let monitor = BatteryMonitor(eventSpacing: .zero, reader: { .unavailable })
        let controller = BatteryHUDController(monitor: monitor, settings: settings)
        controller.playsAlertSound = false

        let before = snapshot(level: 40)
        controller.handle(BatteryDelivery(
            event: .powerSourceChanged(isPluggedIn: true),
            before: before,
            after: before.applying(.powerSourceChanged(isPluggedIn: true))
        ))
        #expect(controller.presentation?.kind == .charging)
        let firstID = controller.presentation?.id

        controller.present(.charging)
        #expect(controller.presentation?.id != firstID, "each showing gets a fresh token")

        controller.dismiss()
        settings.showPowerStatusNotifications = false
        controller.present(.fullBattery)
        #expect(controller.presentation == nil)
        controller.triggerTestHUD(.fullBattery)
        #expect(controller.presentation?.kind == .fullBattery, "tests bypass the switches")
        #expect(controller.displayedLevel == 100)
        controller.stop()
    }

    @Test
    func testAlertsUseAtollsPreviewLevels() {
        let settings = BatterySettings(defaults: makeDefaults())
        let monitor = BatteryMonitor(eventSpacing: .zero, reader: { .unavailable })
        monitor.ingest(snapshot(level: 3))
        let controller = BatteryHUDController(monitor: monitor, settings: settings)
        controller.triggerTestHUD(.charging)
        #expect(controller.displayedLevel == 12)
        settings.lowBatteryThreshold = 30
        controller.triggerTestHUD(.lowBattery)
        #expect(controller.displayedLevel == 20)
        controller.stop()
    }

    @Test
    func activityFallsBackToCompactUntilTheHostDrawsTheBand() {
        let settings = BatterySettings(defaults: makeDefaults())
        let monitor = BatteryMonitor(eventSpacing: .zero, reader: { .unavailable })
        let controller = BatteryHUDController(monitor: monitor, settings: settings)
        let activity = BatteryHUDActivity(controller: controller, settings: settings, monitor: monitor)
        #expect(activity.priority == ClosedActivityPriority.batteryHUD)
        #expect(!activity.isActivityVisible)

        controller.present(.lowBattery)
        #expect(activity.isActivityVisible)
        #expect(activity.leftWingWidth(in: context()) == 90, "compact until the host asks for the band")
        #expect(activity.bottomBand(in: context()) == nil)

        #expect(activity.bottomBandHeight(in: context()) == 75)
        #expect(activity.leftWingWidth(in: context()) == 75)
        #expect(activity.rightWingWidth(in: context(hovering: true)) == 75)
        #expect(activity.closedBottomCornerRadius(in: context()) == 40)
        #expect(activity.bottomBand(in: context()) != nil)

        settings.lowBatteryHUDStyle = .compact
        #expect(activity.bottomBandHeight(in: context()) == 0)
        #expect(activity.leftWingWidth(in: context()) == 90)
        #expect(activity.closedBottomCornerRadius(in: context()) == nil)

        settings.showPowerStatusNotifications = false
        #expect(!activity.isActivityVisible)
        controller.stop()
    }
}
