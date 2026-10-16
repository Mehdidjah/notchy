import Foundation
import SwiftUI
import Testing
@testable import NotchIsland

// MARK: - Doubles

@MainActor
private final class SoundSpy: TimerSoundPlaying {
    var played: [(name: String, looping: Bool)] = []
    var stopCount = 0

    func play(named name: String, looping: Bool) {
        played.append((name, looping))
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class NotifierSpy: TimerCompletionNotifying {
    var prepareCount = 0
    var completions: [(name: String, duration: TimeInterval)] = []

    func prepare() {
        prepareCount += 1
    }

    func notifyCompletion(name: String, duration: TimeInterval) {
        completions.append((name, duration))
    }
}

/// A clock the test advances by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@MainActor
private func makeDefaults() -> (UserDefaults, String) {
    let suite = "TimerTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

@MainActor
private struct Harness {
    let defaults: UserDefaults
    let suite: String
    let settings: TimerSettings
    let clock: ManualClock
    let sound: SoundSpy
    let notifier: NotifierSpy
    let manager: TimerManager

    init() {
        (defaults, suite) = makeDefaults()
        settings = TimerSettings(defaults: defaults)
        clock = ManualClock()
        sound = SoundSpy()
        notifier = NotifierSpy()
        let clock = clock
        manager = TimerManager(settings: settings, sound: sound, notifier: notifier, clock: { clock.now })
    }

    func tearDown() {
        manager.stop()
        defaults.removePersistentDomain(forName: suite)
    }

    /// Moves the clock and recomputes, the way the tick loop does once a second.
    func advance(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
        manager.tick()
    }
}

// MARK: - Formatting and maths

struct TimerMathTests {
    @Test
    func timeStringUsesMinutesBelowAnHourAndHoursAbove() {
        #expect(TimerFormatting.timeString(0) == "0:00")
        #expect(TimerFormatting.timeString(5) == "0:05")
        #expect(TimerFormatting.timeString(90) == "1:30")
        #expect(TimerFormatting.timeString(25 * 60) == "25:00")
        #expect(TimerFormatting.timeString(3_600) == "1:00:00")
        #expect(TimerFormatting.timeString(3_661) == "1:01:01")
        #expect(TimerFormatting.timeString(-1) == "-0:01")
        #expect(TimerFormatting.timeString(-3_725) == "-1:02:05")
    }

    @Test
    func presetDurationIsPaddedPositional() {
        #expect(TimerPreset(name: "Focus", duration: 25 * 60, colorComponents: .systemOrange).formattedDuration == "25:00")
        #expect(TimerPreset(name: "Break", duration: 5 * 60, colorComponents: .systemGreen).formattedDuration == "05:00")
        #expect(TimerPreset(name: "Long", duration: 90 * 60, colorComponents: .systemBlue).formattedDuration == "01:30:00")
    }

    @Test
    func durationComponentsRoundTrip() {
        let components = TimerDurationComponents(duration: 3_725)
        #expect(components == TimerDurationComponents(hours: 1, minutes: 2, seconds: 5))
        #expect(components.duration == 3_725)
        #expect(TimerDurationComponents(duration: -4) == TimerDurationComponents())
    }

    @Test
    func progressClampsWhileCountingAndGrowsPastOneInOvertime() {
        #expect(TimerProgressMath.progress(totalDuration: 0, elapsed: 10, remaining: 0, isOvertime: false) == 0)
        #expect(TimerProgressMath.progress(totalDuration: 100, elapsed: 25, remaining: 75, isOvertime: false) == 0.25)
        #expect(TimerProgressMath.progress(totalDuration: 100, elapsed: 500, remaining: 0, isOvertime: false) == 1)
        #expect(TimerProgressMath.progress(totalDuration: 100, elapsed: 100, remaining: -50, isOvertime: true) == 1.5)
        #expect(TimerProgressMath.progress(totalDuration: 100, elapsed: 100, remaining: -500, isOvertime: true) == 2)
        #expect(TimerProgressMath.clamped(1.7) == 1)
        #expect(TimerProgressMath.clamped(-0.2) == 0)
    }

    @Test
    func colorRampGoesGreenThenYellowThenRed() {
        #expect(TimerColorRamp.color(progress: 0.1, isOvertime: false) == .green)
        #expect(TimerColorRamp.color(progress: 0.59, isOvertime: false) == .green)
        #expect(TimerColorRamp.color(progress: 0.6, isOvertime: false) == Color(red: 0.5, green: 1, blue: 0))
        #expect(TimerColorRamp.color(progress: 0.75, isOvertime: false) == Color(red: 0.75, green: 1, blue: 0))
        #expect(TimerColorRamp.color(progress: 0.9, isOvertime: false) == .red)
        #expect(TimerColorRamp.color(progress: 0.2, isOvertime: true) == .red)
    }

    @Test
    func countdownClockCountsWholeSecondsFromTheWallClock() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var clock = TimerCountdownClock(totalDuration: 10, startedAt: start)

        #expect(clock.remaining(at: start) == 10)
        #expect(clock.remaining(at: start.addingTimeInterval(0.9)) == 10)
        #expect(clock.remaining(at: start.addingTimeInterval(1.0)) == 9)
        #expect(clock.remaining(at: start.addingTimeInterval(2.9996)) == 7, "a sleep that wakes a hair early still shows the new second")
        #expect(clock.remaining(at: start.addingTimeInterval(10)) == 0)
        #expect(clock.remaining(at: start.addingTimeInterval(13)) == -3)
        #expect(clock.elapsed(at: start.addingTimeInterval(13)) == 10, "elapsed stops at the total")

        clock.pause(at: start.addingTimeInterval(4))
        #expect(clock.isPaused)
        #expect(clock.remaining(at: start.addingTimeInterval(400)) == 6, "nothing passes while paused")
        #expect(clock.delayUntilNextTick(from: start.addingTimeInterval(400)) == nil)

        clock.resume(at: start.addingTimeInterval(400))
        #expect(clock.remaining(at: start.addingTimeInterval(401.5)) == 5)
        #expect(clock.remaining(at: start.addingTimeInterval(406)) == 0)
    }

    @Test
    func nextTickLandsOnTheNextWholeSecond() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let clock = TimerCountdownClock(totalDuration: 60, startedAt: start)
        let delay = try! #require(clock.delayUntilNextTick(from: start.addingTimeInterval(3.25)))
        #expect(abs(delay - 0.75) < 0.001)
        let exact = try! #require(clock.delayUntilNextTick(from: start.addingTimeInterval(4)))
        #expect(abs(exact - 1) < 0.001)
    }
}

// MARK: - Manager

@MainActor
struct TimerManagerTests {
    @Test
    func startPublishesTheRunAndCountsDown() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager

        manager.start(duration: 5, name: "Tea")
        #expect(manager.isActive)
        #expect(manager.isRunning)
        #expect(manager.name == "Tea")
        #expect(manager.totalDuration == 5)
        #expect(manager.remainingTime == 5)
        #expect(manager.statusText == "Running")
        #expect(manager.statusBadgeText == nil)
        #expect(manager.formattedRemainingTime == "0:05")
        #expect(harness.notifier.prepareCount == 1)

        harness.advance(2)
        #expect(manager.remainingTime == 3)
        #expect(manager.elapsedTime == 2)
        #expect(manager.progress == 0.4)
        #expect(manager.formattedRemainingTime == "0:03")
        #expect(harness.sound.played.isEmpty)
    }

    @Test
    func zeroDurationIsIgnored() {
        let harness = Harness()
        defer { harness.tearDown() }

        harness.manager.start(duration: 0)
        #expect(!harness.manager.isActive)
        harness.manager.start(duration: 0.4)
        #expect(!harness.manager.isActive)
    }

    @Test
    func reachingZeroRingsOnceNotifiesAndRunsIntoOvertime() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager

        manager.start(duration: 3, name: "Eggs")
        harness.advance(3)
        #expect(manager.remainingTime == 0)
        #expect(manager.isFinished)
        #expect(!manager.isOvertime, "the zero tick is 'completed', overtime begins a second later")
        #expect(manager.statusBadgeText == "Completed")
        #expect(manager.progress == 1)
        #expect(harness.sound.played.count == 1)
        #expect(harness.sound.played.first?.name == TimerSettings.defaultSoundName)
        #expect(harness.sound.played.first?.looping == true)
        #expect(harness.notifier.completions.count == 1)
        #expect(harness.notifier.completions.first?.name == "Eggs")
        #expect(harness.notifier.completions.first?.duration == 3)

        harness.advance(1)
        #expect(manager.remainingTime == -1)
        #expect(manager.isOvertime)
        #expect(manager.formattedRemainingTime == "-0:01")
        #expect(manager.statusText == "Overtime")
        #expect(manager.statusBadgeText == "Overtime")
        #expect(manager.progress > 1)
        #expect(manager.isActive, "overtime continues until the user stops the timer")
        #expect(harness.sound.played.count == 1, "the alert is started once and loops")

        harness.advance(1)
        #expect(manager.remainingTime == -2)
        #expect(harness.notifier.completions.count == 1)
    }

    @Test
    func soundAndNotificationHonourSettings() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.settings.soundEnabled = false
        harness.settings.notificationsEnabled = false

        harness.manager.start(duration: 1)
        #expect(harness.notifier.prepareCount == 0)
        harness.advance(1)
        #expect(harness.sound.played.isEmpty)
        #expect(harness.notifier.completions.isEmpty)
    }

    @Test
    func pauseFreezesTimeAndResumeContinuesFromWhereItStopped() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager

        manager.start(duration: 10)
        harness.advance(4)
        manager.pause()
        #expect(manager.isPaused)
        #expect(!manager.isRunning)
        #expect(manager.statusText == "Paused")
        #expect(manager.statusBadgeText == "Paused")

        harness.advance(60)
        #expect(manager.remainingTime == 6, "ticks while paused change nothing")

        manager.resume()
        #expect(!manager.isPaused)
        harness.advance(2)
        #expect(manager.remainingTime == 4)
        #expect(manager.elapsedTime == 6)

        manager.togglePause()
        #expect(manager.isPaused)
        manager.togglePause()
        #expect(!manager.isPaused)
    }

    @Test
    func stopResetsEverythingAndSilencesTheAlert() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager
        let preset = harness.settings.presets[0]

        manager.start(preset: preset)
        #expect(manager.activePresetID == preset.id)
        #expect(manager.activePreset == preset)
        #expect(manager.name == "Focus")
        #expect(manager.totalDuration == 25 * 60)
        harness.advance(25 * 60)
        #expect(manager.isFinished)
        let stopsBefore = harness.sound.stopCount

        manager.stop()
        #expect(!manager.isActive)
        #expect(manager.remainingTime == 0)
        #expect(manager.totalDuration == 0)
        #expect(manager.name == "Timer")
        #expect(!manager.isFinished)
        #expect(!manager.isOvertime)
        #expect(manager.activePresetID == nil)
        #expect(manager.statusText == "Ready")
        #expect(manager.sessionID == nil)
        #expect(harness.sound.stopCount == stopsBefore + 1)
    }

    @Test
    func startingAgainReplacesTheRun() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager

        manager.start(duration: 30, name: "First")
        harness.advance(10)
        let firstSession = manager.sessionID
        manager.start(duration: 5, name: "Second")
        #expect(manager.sessionID != firstSession)
        #expect(manager.name == "Second")
        #expect(manager.remainingTime == 5)
        #expect(manager.elapsedTime == 0)
        harness.advance(1)
        #expect(manager.remainingTime == 4)
    }

    @Test
    func accentFollowsPresetThenRampThenSolidColour() {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager
        let preset = harness.settings.presets[2]

        manager.start(preset: preset)
        #expect(manager.accentColor == preset.color)

        manager.start(duration: 100, name: "Custom")
        #expect(manager.accentColor == .green)
        harness.advance(95)
        #expect(manager.accentColor == .red)

        harness.settings.iconColorMode = .solid
        #expect(manager.accentColor == TimerColorComponents.systemBlue.color)
    }

    @Test
    func closedNotchLabelFlashesOnStartAndHoldsOnceFinished() async {
        let harness = Harness()
        defer { harness.tearDown() }
        let manager = harness.manager
        manager.transientLabelDuration = .milliseconds(60)

        manager.start(duration: 5, name: "Tea")
        #expect(manager.showsTransientLabel)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!manager.showsTransientLabel, "the name folds away after the flash")

        harness.advance(5)
        #expect(manager.isFinished)
        #expect(manager.showsTransientLabel, "a finished run keeps its name visible")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(manager.showsTransientLabel)

        manager.stop()
        #expect(!manager.showsTransientLabel)
    }

    @Test
    func restoreDefaultsDetectionIgnoresIdentifiers() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TimerSettings(defaults: defaults)
        #expect(settings.presetsMatchDefaults)

        settings.presets = TimerPreset.defaultPresets.map {
            TimerPreset(id: UUID(), name: $0.name, duration: $0.duration, colorComponents: $0.colorComponents)
        }
        #expect(settings.presetsMatchDefaults)

        settings.presets[0].duration = 30 * 60
        #expect(!settings.presetsMatchDefaults)
    }

    @Test
    func tickLoopAdvancesOnItsOwn() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TimerSettings(defaults: defaults)
        settings.soundEnabled = false
        settings.notificationsEnabled = false
        let manager = TimerManager(settings: settings, sound: SoundSpy(), notifier: NotifierSpy())
        defer { manager.stop() }

        manager.start(duration: 60)
        #expect(manager.remainingTime == 60)
        try? await Task.sleep(for: .milliseconds(1_300))
        #expect(manager.remainingTime == 59)
    }
}

// MARK: - Settings and presets

@MainActor
struct TimerSettingsTests {
    @Test
    func defaultsMatchTheReferenceApp() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TimerSettings(defaults: defaults)

        #expect(settings.presets.map(\.name) == ["Focus", "Break", "Deep Work"])
        let expectedDurations: [TimeInterval] = [1_500, 300, 2_700]
        #expect(settings.presets.map(\.duration) == expectedDurations)
        #expect(settings.presets[0].colorComponents == .systemOrange)
        #expect(settings.presets[1].colorComponents == .systemGreen)
        #expect(settings.presets[2].colorComponents == .systemPurple)
        #expect(settings.soundEnabled)
        #expect(settings.soundName == "Glass")
        #expect(settings.notificationsEnabled)
        #expect(settings.liveActivityEnabled)
        #expect(settings.inlineControlsEnabled)
        #expect(settings.showsCountdown)
        #expect(!settings.showsLabel)
        #expect(settings.showsProgress)
        #expect(settings.progressStyle == .bar)
        #expect(settings.iconColorMode == .adaptive)
        #expect(settings.solidColor == .systemBlue)
        #expect(settings.showsPresetsInTab)
        #expect(settings.customDuration == 600)
    }

    @Test
    func presetsPersistAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TimerSettings(defaults: defaults)
        first.addPreset()
        first.presets[3].name = "Stretch"
        first.presets[3].duration = 90
        first.presets[3].colorComponents = TimerColorComponents(red: 0.1, green: 0.2, blue: 0.3)
        first.removePreset(id: first.presets[1].id)
        let expected = first.presets

        let second = TimerSettings(defaults: defaults)
        #expect(second.presets == expected)
        #expect(second.presets.count == 3)
        #expect(second.presets.last?.name == "Stretch")
        #expect(second.presets.last?.duration == 90)
        #expect(second.preset(withID: expected[0].id) == expected[0])
        #expect(second.preset(withID: nil) == nil)

        second.restoreDefaultPresets()
        let third = TimerSettings(defaults: defaults)
        #expect(third.presets == TimerPreset.defaultPresets)
    }

    @Test
    func emptyPresetListStaysEmptyButCorruptDataFallsBackToDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = TimerSettings(defaults: defaults)
        settings.presets = []
        #expect(TimerSettings(defaults: defaults).presets.isEmpty)

        defaults.set(Data("not json".utf8), forKey: TimerSettings.Key.presets)
        #expect(TimerSettings(defaults: defaults).presets == TimerPreset.defaultPresets)
    }

    @Test
    func scalarSettingsRoundTripThroughDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TimerSettings(defaults: defaults)
        first.soundEnabled = false
        first.soundName = "Ping"
        first.liveActivityEnabled = false
        first.progressStyle = .ring
        first.iconColorMode = .solid
        first.solidColor = TimerColorComponents(red: 1, green: 0, blue: 0.5)
        first.customDuration = 90
        first.showsLabel = true

        let second = TimerSettings(defaults: defaults)
        #expect(!second.soundEnabled)
        #expect(second.soundName == "Ping")
        #expect(!second.liveActivityEnabled)
        #expect(second.progressStyle == .ring)
        #expect(second.iconColorMode == .solid)
        #expect(second.solidColor == TimerColorComponents(red: 1, green: 0, blue: 0.5))
        #expect(second.customDuration == 90)
        #expect(second.showsLabel)

        defaults.set("Klaxon", forKey: TimerSettings.Key.soundName)
        #expect(TimerSettings(defaults: defaults).soundName == "Glass", "unknown sound names fall back")
    }
}

// MARK: - Closed-notch layout

@MainActor
struct TimerLiveActivityLayoutTests {
    private func inputs(
        height: CGFloat = 20,
        name: String = "Focus",
        countdown: String = "24:59",
        overtime: Bool = false,
        countdownShown: Bool = true,
        label: Bool = false,
        progress: Bool = true,
        style: TimerProgressStyle = .bar,
        controls: Bool = true
    ) -> TimerLiveActivityLayout.Inputs {
        .init(
            contentHeight: height,
            name: name,
            countdownText: countdown,
            isFinished: overtime,
            isOvertime: overtime,
            showsCountdown: countdownShown,
            showsLabel: label,
            showsProgress: progress,
            progressStyle: style,
            showsControls: controls
        )
    }

    @Test
    func contentHeightShrinksWhileIdleAndFillsOnHover() {
        #expect(TimerLiveActivityLayout.contentHeight(collapsedHeight: 32, isHovering: false) == 20)
        #expect(TimerLiveActivityLayout.contentHeight(collapsedHeight: 40, isHovering: true) == 32)
        #expect(TimerLiveActivityLayout.contentHeight(collapsedHeight: 5, isHovering: false) == 0)
    }

    @Test
    func defaultWingsAreIconLeftAndCountdownWithControlsRight() {
        let layout = TimerLiveActivityLayout(inputs())
        #expect(!layout.showsInfoSection)
        #expect(layout.iconWidth == 20)
        #expect(layout.leftWingWidth == 31)
        #expect(layout.inlineButtonSize == 20)
        #expect(layout.controlCount == 2)
        #expect(layout.controlsWidth == 50)
        #expect(layout.countdownWidth >= 72)
        #expect(layout.rightWingWidth == 22 + layout.countdownWidth + 10 + 50)
        #expect(layout.totalWingWidth == layout.leftWingWidth + layout.rightWingWidth)
    }

    @Test
    func overtimeShowsASingleStopButtonAndTheLabel() {
        let layout = TimerLiveActivityLayout(inputs(overtime: true, label: true))
        #expect(layout.controlCount == 1)
        #expect(layout.controlsWidth == 20)
        #expect(layout.showsInfoSection)
        #expect(layout.infoNeedsMarquee)
        #expect(layout.leftWingWidth == 20 + 11 + 8 + layout.infoWidth)
    }

    @Test
    func ringPlacementFollowsTheCountdown() {
        let wrapping = TimerLiveActivityLayout(inputs(height: 32, style: .ring))
        #expect(wrapping.ringWrapsIcon)
        #expect(!wrapping.ringOnRight)
        #expect(wrapping.iconWidth == 28)
        #expect(wrapping.iconRingDiameter == 28)
        #expect(wrapping.rightRingWidth == 0)

        let aside = TimerLiveActivityLayout(inputs(height: 32, countdownShown: false, style: .ring))
        #expect(aside.ringOnRight)
        #expect(aside.rightRingWidth == 30)
        #expect(aside.rightRingDiameter == 26)
        #expect(aside.countdownWidth == 0)
        #expect(aside.rightWingWidth == 22 + 30 + 10 + aside.controlsWidth)
    }

    @Test
    func barWithoutCountdownMovesIntoTheInfoSection() {
        let layout = TimerLiveActivityLayout(inputs(countdownShown: false, controls: false))
        #expect(layout.showsBarInInfo)
        #expect(layout.showsInfoSection)
        let expectedInfoWidth: CGFloat = 64 + 18
        #expect(layout.infoWidth == expectedInfoWidth)
        #expect(layout.rightWingWidth == 22)
    }

    @Test
    func longNamesAreClampedAndMarqueed() {
        let layout = TimerLiveActivityLayout(inputs(name: String(repeating: "Very long timer name ", count: 4), label: true))
        let expectedInfoWidth: CGFloat = 220 + 18
        #expect(layout.infoWidth == expectedInfoWidth)
        #expect(layout.infoNeedsMarquee)
        #expect(layout.infoTextWidth <= 220 + 18 - 10 - 6)
    }

    @Test
    func presentableOnlyWhileActiveAndEnabled() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TimerSettings(defaults: defaults)
        let manager = TimerManager(settings: settings, sound: SoundSpy(), notifier: NotifierSpy())
        defer { manager.stop() }

        #expect(!TimerLiveActivityView.isPresentable(manager: manager, settings: settings))
        #expect(TimerLiveActivityLayout.extraCollapsedWidth(collapsedHeight: 32, isHovering: false, manager: manager, settings: settings) == 0)

        manager.start(duration: 60)
        #expect(TimerLiveActivityView.isPresentable(manager: manager, settings: settings))
        let flashing = try! #require(TimerLiveActivityLayout.current(collapsedHeight: 32, isHovering: false, manager: manager, settings: settings))
        #expect(flashing.showsLabel, "the name flashes right after a start")
        #expect(flashing.showsInfoSection)
        let extra = TimerLiveActivityLayout.extraCollapsedWidth(collapsedHeight: 32, isHovering: false, manager: manager, settings: settings)
        #expect(extra == flashing.totalWingWidth)
        #expect(extra > 100)

        settings.liveActivityEnabled = false
        #expect(!TimerLiveActivityView.isPresentable(manager: manager, settings: settings))
    }
}
