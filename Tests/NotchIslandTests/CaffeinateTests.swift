import Foundation
import IOKit.pwr_mgt
import Testing
@testable import NotchIsland

@MainActor
private final class FakePowerAssertions: CaffeinatePowerAssertions {
    var nextID: IOPMAssertionID = 100
    var failsCreation = false
    private(set) var held: [IOPMAssertionID: CaffeinateAssertionKind] = [:]
    private(set) var log: [String] = []

    func create(_ kind: CaffeinateAssertionKind, reason: String) -> IOPMAssertionID? {
        guard !failsCreation else { return nil }
        nextID += 1
        held[nextID] = kind
        log.append("create \(kind)")
        return nextID
    }

    func release(_ id: IOPMAssertionID) {
        held[id] = nil
        log.append("release \(id)")
    }

    var heldKinds: Set<CaffeinateAssertionKind> { Set(held.values) }
}

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
struct CaffeinateTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CaffeinateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeController(
        defaults: UserDefaults? = nil
    ) -> (CaffeinateController, FakePowerAssertions, TestClock, CaffeinateSettings) {
        let settings = CaffeinateSettings(defaults: defaults ?? makeDefaults())
        let assertions = FakePowerAssertions()
        let clock = TestClock()
        let controller = CaffeinateController(settings: settings, assertions: assertions, now: { clock.now })
        return (controller, assertions, clock, settings)
    }

    // MARK: Durations

    @Test
    func durationsMatchAtollsChoices() {
        #expect(CaffeinateDuration.allCases.map(\.rawValue) == [
            "indefinite", "fifteenMinutes", "thirtyMinutes", "oneHour", "twoHours", "fourHours"
        ])
        #expect(CaffeinateDuration.indefinite.seconds == nil)
        #expect(CaffeinateDuration.fifteenMinutes.seconds == 900)
        #expect(CaffeinateDuration.thirtyMinutes.seconds == 1_800)
        #expect(CaffeinateDuration.oneHour.seconds == 3_600)
        #expect(CaffeinateDuration.twoHours.seconds == 7_200)
        #expect(CaffeinateDuration.fourHours.seconds == 14_400)
        #expect(CaffeinateDuration.indefinite.displayName == "Until turned off")
        #expect(CaffeinateDuration.oneHour.displayName == "1 hour")
    }

    @Test
    func remainingLabelRoundsUpAndAddsHoursFromAnHour() {
        #expect(CaffeinateDuration.remainingLabel(0) == "0:00")
        #expect(CaffeinateDuration.remainingLabel(-5) == "0:00")
        #expect(CaffeinateDuration.remainingLabel(0.4) == "0:01")
        #expect(CaffeinateDuration.remainingLabel(59.2) == "1:00")
        #expect(CaffeinateDuration.remainingLabel(900) == "15:00")
        #expect(CaffeinateDuration.remainingLabel(3_599) == "59:59")
        #expect(CaffeinateDuration.remainingLabel(3_600) == "1:00:00")
        #expect(CaffeinateDuration.remainingLabel(14_400) == "4:00:00")
    }

    // MARK: Settings

    @Test
    func settingsUseAtollDefaultsAndPersist() {
        let defaults = makeDefaults()
        let settings = CaffeinateSettings(defaults: defaults)
        #expect(settings.isEnabled)
        #expect(settings.showHeaderButton)
        #expect(settings.defaultDuration == .indefinite)
        #expect(settings.keepsDisplayAwake)

        settings.defaultDuration = .twoHours
        settings.keepsDisplayAwake = false
        settings.showHeaderButton = false
        #expect(defaults.string(forKey: CaffeinateSettings.Key.defaultDuration) == "twoHours")

        let reloaded = CaffeinateSettings(defaults: defaults)
        #expect(reloaded.defaultDuration == .twoHours)
        #expect(reloaded.keepsDisplayAwake == false)
        #expect(reloaded.showHeaderButton == false)
    }

    // MARK: Sessions

    @Test
    func timedSessionHoldsSystemAndDisplayAssertionsAndCountsDown() {
        let (controller, assertions, clock, _) = makeController()
        controller.activate(for: .fifteenMinutes)

        #expect(controller.isActive)
        #expect(controller.activeDuration == .fifteenMinutes)
        #expect(controller.remainingTime == 900)
        #expect(controller.expiresAt == clock.now.addingTimeInterval(900))
        #expect(assertions.heldKinds == [.preventSystemSleep, .preventDisplaySleep])
        #expect(controller.statusText == "15:00 left")

        clock.advance(61)
        controller.tick()
        #expect(controller.remainingTime == 839)
        #expect(controller.statusText == "13:59 left")

        clock.advance(839)
        controller.tick()
        #expect(controller.isActive == false)
        #expect(controller.remainingTime == nil)
        #expect(controller.activeDuration == nil)
        #expect(assertions.held.isEmpty)
        #expect(controller.statusText == "Off")
    }

    @Test
    func indefiniteSessionHasNoCountdown() {
        let (controller, _, _, _) = makeController()
        controller.activate(for: .indefinite)
        #expect(controller.isActive)
        #expect(controller.expiresAt == nil)
        #expect(controller.remainingTime == nil)
        #expect(controller.statusText == "On until turned off")
        controller.tick()
        #expect(controller.isActive)
    }

    @Test
    func displayOptionOffHoldsOnlyTheSystemAssertion() {
        let (controller, assertions, _, settings) = makeController()
        settings.keepsDisplayAwake = false
        controller.activate(for: .oneHour)
        #expect(assertions.heldKinds == [.preventSystemSleep])
    }

    @Test
    func choosingAnotherDurationReplacesTheSessionInsteadOfStacking() {
        let (controller, assertions, _, _) = makeController()
        controller.activate(for: .fifteenMinutes)
        let first = Set(assertions.held.keys)
        controller.activate(for: .twoHours)

        #expect(assertions.held.count == 2)
        #expect(first.isDisjoint(with: assertions.held.keys))
        #expect(controller.activeDuration == .twoHours)
        #expect(controller.remainingTime == 7_200)
    }

    @Test
    func toggleStartsDefaultDurationThenStops() {
        let (controller, assertions, _, settings) = makeController()
        settings.defaultDuration = .thirtyMinutes
        controller.toggle()
        #expect(controller.activeDuration == .thirtyMinutes)
        controller.toggle()
        #expect(controller.isActive == false)
        #expect(assertions.held.isEmpty)
    }

    @Test
    func disabledFeatureNeverHoldsAnAssertion() {
        let (controller, assertions, _, settings) = makeController()
        settings.isEnabled = false
        controller.activate(for: .oneHour)
        #expect(controller.isActive == false)
        #expect(assertions.held.isEmpty)
    }

    @Test
    func failedAssertionLeavesKeepAwakeOff() {
        let (controller, assertions, _, _) = makeController()
        assertions.failsCreation = true
        controller.activate(for: .oneHour)
        #expect(controller.isActive == false)
    }

    @Test
    func turningTheFeatureOffEndsARunningSession() {
        let (controller, assertions, _, settings) = makeController()
        controller.startObserving()
        defer { controller.stopObserving() }
        controller.activate(for: .indefinite)
        #expect(controller.isActive)

        settings.isEnabled = false
        #expect(controller.isActive == false)
        #expect(assertions.held.isEmpty)
    }

    @Test
    func displayOptionAppliesToARunningSession() {
        let (controller, assertions, _, settings) = makeController()
        controller.startObserving()
        defer { controller.stopObserving() }
        controller.activate(for: .indefinite)
        #expect(assertions.heldKinds == [.preventSystemSleep, .preventDisplaySleep])

        settings.keepsDisplayAwake = false
        #expect(assertions.heldKinds == [.preventSystemSleep])

        settings.keepsDisplayAwake = true
        #expect(assertions.heldKinds == [.preventSystemSleep, .preventDisplaySleep])
        #expect(controller.isActive)
    }

    @Test
    func popoverPresentationIsReportedOncePerChange() {
        let (controller, _, _, _) = makeController()
        var reports: [Bool] = []
        controller.onPopoverPresentationChanged = { reports.append($0) }
        controller.setPopoverPresented(true)
        controller.setPopoverPresented(true)
        controller.setPopoverPresented(false)
        #expect(reports == [true, false])
        #expect(controller.isPopoverPresented == false)
    }

    @Test
    func liveIOKitAssertionCanBeTakenAndReleased() {
        let assertions = IOKitCaffeinateAssertions()
        let id = assertions.create(.preventSystemSleep, reason: "NotchIsland unit test")
        #expect(id != nil)
        if let id { assertions.release(id) }
    }
}
