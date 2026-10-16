import AppKit
import Foundation
import Testing
@testable import Notchy

@MainActor
struct BrightnessTests {
    nonisolated private static let afterKeyPress = InputRecency(sinceKeyOrPointer: 0.2, sinceAnyInput: 0.2)
    nonisolated private static let afterTyping = InputRecency(sinceKeyOrPointer: 30, sinceAnyInput: 0.3)
    nonisolated private static let afterPointerMove = InputRecency(sinceKeyOrPointer: 30, sinceAnyInput: 0.05)
    nonisolated private static let idle = InputRecency(sinceKeyOrPointer: 30, sinceAnyInput: 30)

    /// A monitor whose input recency a test can change between readings.
    private func makeMonitor(
        reader: @escaping @MainActor () -> BrightnessReading? = { nil },
        recency: RecencyBox,
        keyTargetsBuiltIn: @escaping @MainActor () -> Bool = { true }
    ) -> (BrightnessMonitor, ReportLog) {
        let monitor = BrightnessMonitor(
            reader: reader,
            inputRecency: { recency.value },
            keyTargetsBuiltIn: keyTargetsBuiltIn
        )
        let log = ReportLog()
        monitor.onUserChange = { log.levels.append($0) }
        return (monitor, log)
    }

    /// Feeds `levels` 0.1 s apart from `start`; returns the time after the last one.
    @discardableResult
    private func feed(_ monitor: BrightnessMonitor, _ levels: [Double], headroom: Double = 1, from start: Date) -> Date {
        var time = start
        for level in levels {
            monitor.ingest(level, headroom: headroom, at: time)
            time = time.addingTimeInterval(0.1)
        }
        return time
    }

    // MARK: Key steps

    @Test
    func keyPressStepIsReportedButAutoBrightnessDriftIsNot() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.afterTyping })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let start = Date()

        // Auto-brightness: 0.5 -> 0.53 over 3 s in tiny steps.
        for i in 0...30 {
            monitor.ingest(0.5 + Double(i) * 0.001, at: start.addingTimeInterval(Double(i) * 0.1))
        }
        #expect(reported.isEmpty)

        // Settle, then a key press ramps 1/16 within 0.3 s.
        let t = start.addingTimeInterval(4)
        monitor.ingest(0.53, at: t)
        monitor.ingest(0.53, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.56, at: t.addingTimeInterval(0.2))
        monitor.ingest(0.5925, at: t.addingTimeInterval(0.3))
        #expect(reported == [0.5925], "a full step shows once it has moved past the coarse threshold")

        // The same gesture keeps reporting until the level settles.
        monitor.ingest(0.6, at: t.addingTimeInterval(0.4))
        #expect(reported.last == 0.6)
    }

    @Test
    func fineStepShowsRightAfterAMediaKey() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.afterKeyPress })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let t = Date()
        monitor.ingest(0.5, at: t)
        monitor.ingest(0.5, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.5156, at: t.addingTimeInterval(0.2))
        #expect(reported == [0.5156], "a 1/64 Shift-Option step")
    }

    @Test
    func idleDimmingWithoutInputIsIgnored() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.idle })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let t = Date()
        monitor.ingest(0.8, at: t)
        monitor.ingest(0.6, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.4, at: t.addingTimeInterval(0.2))
        #expect(reported.isEmpty)
        #expect(monitor.isIdleDimmed)
    }

    // MARK: EDR headroom

    @Test
    func headroomChangeRebaselinesSilently() {
        let recency = RecencyBox(Self.afterKeyPress)
        let (monitor, log) = makeMonitor(recency: recency)
        let t = Date()
        feed(monitor, [0.5, 0.5], headroom: 1, from: t)

        // HDR content appears right after a click: the headroom ramps to 1.2 and the
        // converted level wobbles while the two reads are out of step.
        monitor.ingest(0.5625, headroom: 1.1, at: t.addingTimeInterval(0.2))
        monitor.ingest(0.53, headroom: 1.2, at: t.addingTimeInterval(1.0))
        monitor.ingest(0.5, headroom: 1.2, at: t.addingTimeInterval(2.4))
        monitor.ingest(0.53, headroom: 1.2, at: t.addingTimeInterval(3.4))
        #expect(log.levels.isEmpty, "nothing shows while the headroom moved within 2.5 s")

        // Once it has held still for 2.5 s, a real key step shows again.
        let later = t.addingTimeInterval(4)
        feed(monitor, [0.53, 0.53], headroom: 1.2, from: later)
        monitor.ingest(0.5925, headroom: 1.2, at: later.addingTimeInterval(0.2))
        #expect(log.levels == [0.5925])
    }

    @Test
    func tinyHeadroomJitterDoesNotHoldBackAKeyStep() {
        let (monitor, log) = makeMonitor(recency: RecencyBox(Self.afterKeyPress))
        let t = Date()
        feed(monitor, [0.5, 0.5], headroom: 1.2, from: t)
        monitor.ingest(0.5625, headroom: 1.204, at: t.addingTimeInterval(0.2))
        #expect(log.levels == [0.5625], "a 0.3 % headroom change is noise")
    }

    @Test
    func brightnessKeyStillShowsWhileTheHeadroomMoves() {
        let (monitor, log) = makeMonitor(recency: RecencyBox(Self.idle))
        let t = Date()
        feed(monitor, [0.5, 0.5], headroom: 2, from: t)
        // XDR: with HDR on screen the headroom moves with every brightness step.
        monitor.brightnessKeyPressed(.up, at: t.addingTimeInterval(0.15))
        monitor.ingest(0.5625, headroom: 1.8, at: t.addingTimeInterval(0.2))
        #expect(log.levels == [0.5625])
    }

    @Test
    func restartDuringAnEDRTransitionKeepsTheQuietPeriod() {
        let current = Box(BrightnessReading(level: 0.5, headroom: 1))
        let (monitor, log) = makeMonitor(reader: { current.value }, recency: RecencyBox(Self.afterKeyPress))
        monitor.start()
        monitor.stop()

        // A restart with the headroom unchanged (display wake) holds nothing back.
        monitor.start()
        let t = feed(monitor, [0.5, 0.5625, 0.5625], from: Date())
        #expect(log.levels == [0.5625])
        monitor.stop()

        // HDR content appears right after a click and the monitor restarts meanwhile.
        // AppKit already reports the new headroom while the backlight output is still
        // ramping towards it, so the converted level climbs for a while.
        current.value = BrightnessReading(level: 0.34, headroom: 1.6)
        monitor.start()
        defer { monitor.stop() }
        feed(monitor, [0.38, 0.42, 0.46, 0.5, 0.5], headroom: 1.6, from: t)
        #expect(log.levels == [0.5625], "the restart keeps the EDR quiet period")
    }

    @Test
    func physicalNitsAreDividedByTheCurrentHeadroom() {
        // The same slider position read with and without HDR content on screen.
        let withHDR = BrightnessCurve.sliderLevel(physicalNits: 201.517, headroom: 1.2, backlightCapNits: 600)
        let withoutHDR = BrightnessCurve.sliderLevel(physicalNits: 167.931, headroom: 1.0, backlightCapNits: 600)
        #expect(abs(withHDR - 0.5625) < 0.01)
        #expect(abs(withoutHDR - 0.5625) < 0.01)
        #expect(abs(BrightnessCurve.sliderLevel(physicalNits: 600, headroom: 1, backlightCapNits: nil) - 1) < 0.0001)
        #expect(BrightnessCurve.sliderLevel(physicalNits: 300, headroom: 0.5, backlightCapNits: 600)
            == BrightnessCurve.sliderLevel(physicalNits: 300, headroom: 1, backlightCapNits: 600),
            "a headroom below 1 is treated as SDR")
    }

    // MARK: Idle dimming and display sleep

    @Test
    func returnFromIdleDimmingIsAbsorbedOverSeveralPolls() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5, 0.5], from: Date())
        #expect(monitor.presenceLevel == 0.5)

        // Away: macOS dims the screen with nobody at the keyboard.
        recency.value = Self.idle
        t = feed(monitor, [0.4, 0.25, 0.1, 0.08, 0.08], from: t.addingTimeInterval(120))
        #expect(monitor.isIdleDimmed)

        // Back: a pointer move wakes it and macOS ramps back to where the user left it. The
        // first poll after the input can still read the dimmed level.
        recency.value = Self.afterPointerMove
        t = feed(monitor, [0.08, 0.07, 0.2, 0.45, 0.5, 0.5], from: t.addingTimeInterval(30))
        #expect(log.levels.isEmpty, "the restore ramp, and the dim ramp's last poll, are not key presses")
        #expect(!monitor.isIdleDimmed, "settled back at the presence level")

        // A real full step after that still shows.
        recency.value = Self.afterTyping
        monitor.ingest(0.5625, at: t)
        #expect(log.levels == [0.5625])
    }

    @Test
    func wakeFromDarkBacklightIsAbsorbed() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())

        recency.value = Self.idle
        t = feed(monitor, [0.1, 0, 0, 0], from: t.addingTimeInterval(300))
        #expect(monitor.isIdleDimmed)

        // A key wakes the display and the level jumps straight back.
        recency.value = Self.afterTyping
        t = feed(monitor, [0.5, 0.5], from: t.addingTimeInterval(60))
        #expect(log.levels.isEmpty)
        #expect(!monitor.isIdleDimmed)

        // Same from dark again, this time with the restore ramping over several polls.
        recency.value = Self.idle
        t = feed(monitor, [0, 0], from: t.addingTimeInterval(300))
        recency.value = Self.afterPointerMove
        t = feed(monitor, [0.3, 0.5, 0.5], from: t.addingTimeInterval(60))
        #expect(log.levels.isEmpty)
    }

    @Test
    func risePastThePresenceLevelAfterIdleIsStillAKeyStep() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())
        recency.value = Self.idle
        t = feed(monitor, [0.3, 0.3], from: t.addingTimeInterval(60))
        recency.value = Self.afterTyping
        t = feed(monitor, [0.5], from: t.addingTimeInterval(10))
        #expect(monitor.isIdleDimmed, "restored, but not yet seen holding still")
        // A full step past the level the user left is a key press, not the restore.
        monitor.ingest(0.5625, at: t)
        #expect(log.levels == [0.5625])
        #expect(!monitor.isIdleDimmed)
    }

    @Test
    func keyOrClickRightAfterDimmingReportsNormally() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())
        recency.value = Self.idle
        t = feed(monitor, [0.3, 0.3], from: t.addingTimeInterval(60))
        #expect(monitor.isIdleDimmed)
        recency.value = Self.afterKeyPress
        monitor.ingest(0.35, at: t)
        #expect(log.levels == [0.35])
        #expect(!monitor.isIdleDimmed)
    }

    @Test
    func autoBrightnessRiseWithoutInputMovesThePresenceLevel() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())

        // Reading without touching anything while auto-brightness raises the level.
        recency.value = Self.idle
        let rise = (1...10).map { 0.5 + Double($0) * 0.01 }
        t = feed(monitor, rise + [0.6, 0.6], from: t.addingTimeInterval(60))
        #expect(!monitor.isIdleDimmed, "a rise with nobody around is auto-brightness, not idle dimming")
        #expect(monitor.presenceLevel == 0.6)

        // Then macOS dims the idle screen, and a pointer move brings it back to 0.6.
        t = feed(monitor, [0.45, 0.3, 0.3], from: t.addingTimeInterval(60))
        #expect(monitor.isIdleDimmed)
        recency.value = Self.afterPointerMove
        t = feed(monitor, [0.3, 0.45, 0.6, 0.6], from: t.addingTimeInterval(30))
        #expect(log.levels.isEmpty, "the restore to the drifted level is not a key press")
        #expect(!monitor.isIdleDimmed)

        // A real full step after that still shows.
        recency.value = Self.afterTyping
        monitor.ingest(0.6625, at: t)
        #expect(log.levels == [0.6625])
    }

    @Test
    func restoreToTheLevelTheDimStartedFromIsAbsorbed() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())

        // Auto-brightness rises with no steady poll before idle dimming starts, so the
        // presence level is still 0.5; the dim starts from 0.6.
        recency.value = Self.idle
        let rise = (1...10).map { 0.5 + Double($0) * 0.01 }
        t = feed(monitor, rise + [0.5, 0.35, 0.3, 0.3], from: t.addingTimeInterval(60))
        #expect(monitor.presenceLevel == 0.5)
        #expect(monitor.isIdleDimmed)
        #expect(monitor.dimmedFrom.map { abs($0 - 0.6) < 0.011 } == true)

        recency.value = Self.afterPointerMove
        t = feed(monitor, [0.3, 0.5, 0.6, 0.6], from: t.addingTimeInterval(30))
        #expect(log.levels.isEmpty)
        #expect(!monitor.isIdleDimmed && monitor.dimmedFrom == nil)
        #expect(monitor.presenceLevel == 0.6)
    }

    @Test
    func steadyLevelWithTheUserBackBecomesThePresenceLevel() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, _) = makeMonitor(recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())
        recency.value = Self.idle
        t = feed(monitor, [0.42, 0.42], from: t.addingTimeInterval(60))
        #expect(monitor.isIdleDimmed)

        // Auto-brightness moved the level while the user was away. Right after they are back
        // the old level still counts: macOS may not have started restoring yet.
        recency.value = Self.afterTyping
        t = feed(monitor, Array(repeating: 0.42, count: 5), from: t.addingTimeInterval(5))
        #expect(monitor.isIdleDimmed)
        #expect(monitor.presenceLevel == 0.5)
        // It holds still with them around: that is the level now.
        t = feed(monitor, Array(repeating: 0.42, count: 30), from: t)
        #expect(!monitor.isIdleDimmed)
        #expect(monitor.presenceLevel == 0.42)
    }

    // MARK: Brightness keys from the tap

    @Test
    func keyAtTheEndOfTheSliderShowsOnce() {
        let current = LevelBox(1)
        let (monitor, log) = makeMonitor(
            reader: { BrightnessReading(level: current.value) },
            recency: RecencyBox(Self.idle)
        )
        monitor.start()
        defer { monitor.stop() }
        let t = Date()

        monitor.brightnessKeyPressed(.up, at: t)
        #expect(log.levels == [1])
        // The level does not move, so polling adds nothing.
        feed(monitor, [1, 1, 1], from: t.addingTimeInterval(0.1))
        #expect(log.levels == [1])

        // Brightness down at the bottom (the move there happened long before).
        current.value = 0
        feed(monitor, [0, 0], from: t.addingTimeInterval(10))
        monitor.brightnessKeyPressed(.down, at: t.addingTimeInterval(10.3))
        #expect(log.levels == [1, 0])
        feed(monitor, [0, 0], from: t.addingTimeInterval(10.4))
        #expect(log.levels == [1, 0])

        // Away from the ends the key moves the level and polling reports it instead.
        current.value = 0.5
        feed(monitor, [0.5, 0.5], from: t.addingTimeInterval(20))
        monitor.brightnessKeyPressed(.down, at: t.addingTimeInterval(20.3))
        monitor.brightnessKeyPressed(.up, at: t.addingTimeInterval(20.35))
        #expect(log.levels == [1, 0])
    }

    @Test
    func keyAtTheEndShowsNothingWhileStopped() {
        let (monitor, log) = makeMonitor(
            reader: { BrightnessReading(level: 1) },
            recency: RecencyBox(Self.afterKeyPress)
        )
        monitor.brightnessKeyPressed(.up)
        #expect(log.levels.isEmpty, "display asleep or HUD off")
    }

    @Test
    func keyAtTheEndShowsOnlyWhenTheBuiltInIsTheTarget() {
        let target = Box(false)
        let (monitor, log) = makeMonitor(
            reader: { BrightnessReading(level: 1) },
            recency: RecencyBox(Self.idle),
            keyTargetsBuiltIn: { target.value }
        )
        monitor.start()
        defer { monitor.stop() }
        monitor.brightnessKeyPressed(.up)
        #expect(log.levels.isEmpty, "the pointer is on another screen, which the key may be adjusting")
        target.value = true
        monitor.brightnessKeyPressed(.up)
        #expect(log.levels == [1])
    }

    @Test
    func brightnessKeyTargetIsTheBuiltInWhenAloneOrUnderThePointer() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(!BuiltInScreen.isBrightnessKeyTarget(builtInFrame: nil, screenCount: 1, pointer: .zero),
                "clamshell: no built-in screen")
        #expect(BuiltInScreen.isBrightnessKeyTarget(builtInFrame: builtIn, screenCount: 1, pointer: CGPoint(x: 9000, y: 0)))
        #expect(BuiltInScreen.isBrightnessKeyTarget(builtInFrame: builtIn, screenCount: 2, pointer: CGPoint(x: 700, y: 500)))
        #expect(BuiltInScreen.isBrightnessKeyTarget(builtInFrame: builtIn, screenCount: 2, pointer: CGPoint(x: 756, y: 982)),
                "the pointer at the notch sits on the top edge")
        #expect(!BuiltInScreen.isBrightnessKeyTarget(builtInFrame: builtIn, screenCount: 2, pointer: CGPoint(x: 2000, y: 500)))
    }

    @Test
    func clamshellHasNoReadingSoKeysShowNothing() {
        #expect(BacklightRegistry.read(headroom: nil) == nil,
                "the panel's framebuffer stays in the registry with the lid closed")
        let (monitor, log) = makeMonitor(
            reader: { BacklightRegistry.read(headroom: nil) },
            recency: RecencyBox(Self.afterKeyPress)
        )
        monitor.start()
        defer { monitor.stop() }
        #expect(monitor.level == nil && !monitor.isAvailable)
        monitor.brightnessKeyPressed(.down)
        monitor.brightnessKeyPressed(.up)
        #expect(log.levels.isEmpty)
    }

    @Test
    func onceTheTapSeesKeysTypingAloneNeverShows() {
        let recency = RecencyBox(Self.afterTyping)
        let (monitor, log) = makeMonitor(reader: { BrightnessReading(level: 0.5) }, recency: recency)
        var t = feed(monitor, [0.5, 0.5], from: Date())

        monitor.brightnessKeyPressed(.up, at: t)
        #expect(monitor.seesBrightnessKeys)
        // Long after that key, a full step with only typing around is not a key press.
        t = t.addingTimeInterval(5)
        t = feed(monitor, [0.5, 0.5625, 0.5625], from: t)
        #expect(log.levels.isEmpty)

        // A key the tap saw is the strongest signal, even with no other input recorded.
        recency.value = Self.idle
        monitor.brightnessKeyPressed(.up, at: t)
        monitor.ingest(0.625, at: t.addingTimeInterval(0.1))
        #expect(log.levels == [0.625])

        // Without the tap, typing is a possible key press again.
        monitor.brightnessKeyTapDidStop()
        recency.value = Self.afterTyping
        t = feed(monitor, [0.625, 0.625], from: t.addingTimeInterval(5))
        monitor.ingest(0.6875, at: t)
        #expect(log.levels == [0.625, 0.6875])
    }

    // MARK: Manager

    private func makeManager(
        brightness: BrightnessMonitor,
        topology: Box<ScreenTopology> = Box(ScreenTopology(screens: []))
    ) -> (SystemHUDManager, SystemHUDPresenter) {
        let suite = "brightness.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SystemHUDSettings(defaults: defaults)
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: IslandActivityCenter())
        let manager = SystemHUDManager(
            settings: settings,
            presenter: presenter,
            volume: VolumeController(),
            microphone: MicrophoneMuteMonitor(),
            interceptor: SystemHUDMediaKeyInterceptor(),
            capsLock: CapsLockMonitor(),
            brightness: brightness,
            screenTopology: { topology.value }
        )
        return (manager, presenter)
    }

    @Test
    func headroomOnlyScreenChangeKeepsTheMonitorRunning() {
        let builtIn = ScreenTopology.Screen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let topology = Box(ScreenTopology(screens: [builtIn]))
        let monitor = BrightnessMonitor(reader: { BrightnessReading(level: 0.5) }, inputRecency: { Self.idle })
        let (manager, _) = makeManager(brightness: monitor, topology: topology)
        manager.screenParametersDidChange()
        monitor.start()
        defer { monitor.stop() }

        // AppKit posts didChangeScreenParameters for every EDR headroom change (each
        // brightness step on an XDR panel showing HDR content); the screens are the same.
        manager.screenParametersDidChange()
        manager.screenParametersDidChange()
        #expect(monitor.isRunning)

        // A display plugged in is a real change: stop now, start over after the delay.
        let external = ScreenTopology.Screen(displayID: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        topology.value = ScreenTopology(screens: [external, builtIn])
        manager.screenParametersDidChange()
        #expect(!monitor.isRunning)
    }

    @Test
    func screenTopologyIgnoresOrderButNotScreensOrFrames() {
        let a = ScreenTopology.Screen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let b = ScreenTopology.Screen(displayID: 7, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
        #expect(ScreenTopology(screens: [a, b]) == ScreenTopology(screens: [b, a]))
        #expect(ScreenTopology(screens: [a]) != ScreenTopology(screens: [a, b]), "lid opened or display added")
        var scaled = a
        scaled.frame.size = CGSize(width: 1800, height: 1169)
        #expect(ScreenTopology(screens: [scaled]) != ScreenTopology(screens: [a]), "resolution changed")
        #expect(ScreenTopology.current() == ScreenTopology.current())
    }

    @Test
    func lockingKeepsTheTapsBrightnessKeyRecord() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.idle })
        let (manager, presenter) = makeManager(brightness: monitor)
        monitor.brightnessKeyPressed(.up)
        #expect(monitor.seesBrightnessKeys)

        // Locking removes the tap while the island is hidden; unlocking installs it again.
        presenter.isScreenLocked = true
        manager.brightnessKeyTapChanged(isObserving: false)
        #expect(monitor.seesBrightnessKeys, "a lock is not a reason to doubt the tap")
        presenter.isScreenLocked = false
        manager.brightnessKeyTapChanged(isObserving: true)
        #expect(monitor.seesBrightnessKeys)

        // Unlocked and still no tap: Accessibility was lost or the HUD was turned off.
        manager.brightnessKeyTapChanged(isObserving: false)
        #expect(!monitor.seesBrightnessKeys)
    }

    // MARK: Curve

    /// SDR points measured on the built-in panel with no HDR content (slider -> nits,
    /// backlight cap 600 nits).
    @Test(arguments: [
        (0.0625, 2.0), (0.125, 3.6696), (0.25, 12.353), (0.3125, 22.666),
        (0.5625, 167.931), (0.75, 289.83), (0.875, 417.0), (1.0, 600.0),
    ])
    func curveMapsMeasuredOutputBackToTheSlider(slider: Double, nits: Double) {
        let full = BrightnessCurve.fullNits(backlightCapNits: 600)
        #expect(full == 600)
        #expect(abs(BrightnessCurve.sliderLevel(nits: nits, fullNits: full) - slider) < 0.01)
    }

    @Test
    func curveClampsAndHandlesOff() {
        #expect(BrightnessCurve.sliderLevel(nits: 0, fullNits: 600) == 0)
        #expect(BrightnessCurve.sliderLevel(nits: 0.01, fullNits: 600) == 0)
        #expect(BrightnessCurve.sliderLevel(nits: 900, fullNits: 600) == 1)
        #expect(BrightnessCurve.fullNits(backlightCapNits: nil) == 600)
        #expect(BrightnessCurve.fullNits(backlightCapNits: 0) == BrightnessCurve.defaultFullNits)
        #expect(BacklightRegistry.fixedPointNits(39_321_600) == 600)
        #expect(BacklightRegistry.fixedPointNits(22_792_960) > 347 && BacklightRegistry.fixedPointNits(22_792_960) < 348)
    }

    // MARK: HUD

    @Test
    func hudUsesSunGlyphsAndALevelPeek() {
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.3) == "sun.min.fill")
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.6) == "sun.min.fill")
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.61) == "sun.max.fill")
        let peek = SystemHUDPresenter.standardSneakPeek(kind: .brightness, level: 0, isBluetooth: false)
        #expect(peek.kind == .brightness)
        #expect(peek.level == 0, "brightness has no muted state")
        #expect(peek.systemImage == "sun.max.fill", "the standard row always draws the large sun")
        #expect(SystemHUDStandardRow.handles(peek))
        let dim = SystemHUDPresenter.standardSneakPeek(kind: .brightness, level: 0.2, isBluetooth: true)
        #expect(dim.systemImage == "sun.max.fill" && dim.level == 0.2)
    }

    @Test
    func registryValuesAreNormalized() {
        #expect(BacklightRegistry.normalized(["min": 0, "max": 65536, "value": 32768]) == 0.5)
        #expect(BacklightRegistry.normalized(["max": 0, "value": 1]) == nil)
        #expect(BacklightRegistry.normalized("nope") == nil)
        let live = BacklightRegistry.read(headroom: BuiltInScreen.currentHeadroom())
        #expect(live == nil || (0...1).contains(live!.level))
        #expect(BuiltInScreen.currentHeadroom().map { $0 >= 1 } ?? true)
    }
}

/// Input recency a test can change between readings.
private final class RecencyBox: @unchecked Sendable {
    var value: InputRecency
    init(_ value: InputRecency) { self.value = value }
}

/// The backlight level the stub reader returns.
@MainActor
private final class LevelBox {
    var value: Double
    init(_ value: Double) { self.value = value }
}

/// A value a stub closure returns and a test changes.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Levels the monitor reported.
@MainActor
private final class ReportLog {
    var levels: [Double] = []
}
