import AppKit
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Notchy

@MainActor
struct SystemHUDTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "systemhud.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func context(
        notchWidth: CGFloat = 189,
        hovering: Bool = false,
        gestureProgress: CGFloat = 0
    ) -> ClosedActivityContext {
        ClosedActivityContext(
            closedHeight: 32,
            notchWidth: notchWidth,
            isHovering: hovering,
            gestureProgress: gestureProgress,
            hasHardwareNotch: true
        )
    }

    // MARK: Inline HUD geometry

    @Test
    func designColumnWidthsMatchInlineHUDTables() {
        #expect(InlineHUDMetrics.designColumns(.level, gestureProgress: 0) == .init(info: 92, trailing: 92))
        #expect(InlineHUDMetrics.designColumns(.level, gestureProgress: 20) == .init(info: 102, trailing: 102))
        #expect(InlineHUDMetrics.designColumns(.capsLock(showsLabel: false), gestureProgress: 0) == .init(info: 56, trailing: 0))
        #expect(InlineHUDMetrics.designColumns(.capsLock(showsLabel: true), gestureProgress: 0) == .init(info: 92, trailing: 88))
        #expect(InlineHUDMetrics.designColumns(.capsLock(showsLabel: false), gestureProgress: 8) == .init(info: 60, trailing: 4))
    }

    @Test(arguments: [false, true])
    func wingWidthsReproduceDesignRowWidthWithOrWithoutHover(hovering: Bool) {
        let contents: [InlineHUDMetrics.Content] = [.level, .capsLock(showsLabel: false), .capsLock(showsLabel: true)]
        for content in contents {
            for progress in [CGFloat(0), 12] {
                let ctx = context(hovering: hovering, gestureProgress: progress)
                let wings = InlineHUDMetrics.wingWidths(content, context: ctx)
                let hostWidth = wings.info + ctx.centerWidth + wings.trailing
                #expect(abs(hostWidth - InlineHUDMetrics.designRowWidth(content, context: ctx)) < 0.001)
                #expect(wings.info >= 0 && wings.trailing >= 0)
            }
        }
    }

    @Test
    func designGapEqualsHardwareNotchWidth() {
        // The closed notch is the hardware gap plus 4 pt; the design centre (width - 20) plus two
        // 8-pt spacings leaves exactly the hardware gap between the columns.
        #expect(InlineHUDMetrics.designGap(notchWidth: 189) == 185)
        let wings = InlineHUDMetrics.wingWidths(.level, context: context())
        #expect(wings.info == 90 && wings.trailing == 90)
        let hovered = InlineHUDMetrics.wingWidths(.level, context: context(hovering: true))
        #expect(hovered.info == 86 && hovered.trailing == 86)
    }

    @Test
    func capsLockWithoutLabelHasNoRightWing() {
        let wings = InlineHUDMetrics.wingWidths(.capsLock(showsLabel: false), context: context())
        #expect(wings.trailing == 0)
        #expect(wings.info == 52)
    }

    // MARK: Symbols and text

    @Test
    func speakerSymbolFollowsDesignThresholds() {
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0) == "speaker.slash.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0.2) == "speaker.wave.1.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0.3) == "speaker.wave.1.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0.5) == "speaker.wave.2.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0.8) == "speaker.wave.2.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 0.81) == "speaker.wave.3.fill")
        #expect(SystemHUDPresenter.speakerSymbolName(for: 1) == "speaker.wave.3.fill")
        #expect(SystemHUDPresenter.volumeSymbolName(for: 0.5, isBluetooth: true) == "headphones")
        #expect(SystemHUDPresenter.microphoneSymbolName(isMuted: true) == "mic.slash.fill")
    }

    @Test
    func percentageIsRoundedAndRightAlignedInThreeColumns() {
        #expect(SystemHUDPresenter.percentageText(for: 0.5) == " 50")
        #expect(SystemHUDPresenter.percentageText(for: 1) == "100")
        #expect(SystemHUDPresenter.percentageText(for: 0.06) == "  6")
        #expect(SystemHUDPresenter.percentageText(for: 1.4) == "100")
    }

    @Test
    func paletteSnapsAndBlendsAtDesignThresholds() {
        #expect(SystemHUDPalette.discreteComponents(for: 0.59) == SystemHUDPalette.green)
        #expect(SystemHUDPalette.discreteComponents(for: 0.6) == SystemHUDPalette.yellow)
        #expect(SystemHUDPalette.discreteComponents(for: 0.85) == SystemHUDPalette.red)
        #expect(SystemHUDPalette.smoothComponents(for: 0.3) == SystemHUDPalette.green)
        let midway = SystemHUDPalette.smoothComponents(for: 0.725)
        #expect(abs(midway.red - (0.2 + 0.93) / 2) < 0.0001)
        #expect(abs(midway.blue - (0.35 + 0.2) / 2) < 0.0001)
        let top = SystemHUDPalette.smoothComponents(for: 1)
        #expect(abs(top.red - SystemHUDPalette.red.red) < 0.0001)
    }

    @Test
    func segmentedBarUsesSixteenSegments() {
        #expect(SystemHUDSegmentedBar.activeCount(for: 0.5) == 8)
        #expect(SystemHUDSegmentedBar.activeCount(for: 1) == 16)
        #expect(SystemHUDSegmentedBar.activeCount(for: 0.03) == 0)
        let expectedSegment: CGFloat = max(3, (54 - 22.5) / 16)
        #expect(SystemHUDSegmentedBar.segmentWidth(totalWidth: 54) == expectedSegment)
        #expect(SystemHUDSegmentedBar.segmentWidth(totalWidth: 10) == 3)
        #expect(SystemHUDProgressBar.height(isInline: true, isDragging: false) == 5)
        #expect(SystemHUDProgressBar.height(isInline: true, isDragging: true) == 8)
        #expect(SystemHUDProgressBar.height(isInline: false, isDragging: false) == 6)
    }

    // MARK: Media keys

    @Test
    func decodesSystemDefinedData1() {
        let volumeUpDown = SystemHUDMediaKey(data1: (0 << 16) | (0xA << 8))
        #expect(volumeUpDown == SystemHUDMediaKey(keyCode: 0, isKeyDown: true, isRepeat: false))
        let muteUp = SystemHUDMediaKey(data1: (7 << 16) | (0xB << 8))
        #expect(muteUp == SystemHUDMediaKey(keyCode: 7, isKeyDown: false, isRepeat: false))
        let repeatDown = SystemHUDMediaKey(data1: (1 << 16) | (0xA << 8) | 1)
        #expect(repeatDown.isRepeat && repeatDown.isKeyDown && repeatDown.keyCode == 1)
        #expect(!SystemHUDMediaKey(data1: (2 << 16) | (0xA << 8)).isVolumeKey)
    }

    @Test
    func mapsKeysToCommandsWithOptionShiftFineStep() {
        let up = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.soundUp, isKeyDown: true, isRepeat: false)
        #expect(SystemHUDMediaKeyCommand.make(for: up, modifiers: []) == .volumeUp(fine: false))
        #expect(SystemHUDMediaKeyCommand.make(for: up, modifiers: [.option, .shift]) == .volumeUp(fine: true))
        #expect(SystemHUDMediaKeyCommand.make(for: up, modifiers: [.option]) == .volumeUp(fine: false))
        let down = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.soundDown, isKeyDown: true, isRepeat: true)
        #expect(SystemHUDMediaKeyCommand.make(for: down, modifiers: []) == .volumeDown(fine: false))
        let mute = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.mute, isKeyDown: true, isRepeat: false)
        #expect(SystemHUDMediaKeyCommand.make(for: mute, modifiers: []) == .toggleMute)
        let heldMute = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.mute, isKeyDown: true, isRepeat: true)
        #expect(SystemHUDMediaKeyCommand.make(for: heldMute, modifiers: []) == nil)
        let release = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.soundUp, isKeyDown: false, isRepeat: false)
        #expect(SystemHUDMediaKeyCommand.make(for: release, modifiers: []) == nil)
        let brightness = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.brightnessUp, isKeyDown: true, isRepeat: false)
        #expect(SystemHUDMediaKeyCommand.make(for: brightness, modifiers: []) == nil)
    }

    @Test
    func brightnessKeysAreReportedButNeverSwallowed() {
        let up = SystemHUDMediaKey(data1: (2 << 16) | (0xA << 8))
        #expect(up.isBrightnessKey && up.brightnessPress == .up)
        let heldDown = SystemHUDMediaKey(data1: (3 << 16) | (0xA << 8) | 1)
        #expect(heldDown.brightnessPress == .down, "a held key keeps stepping, so repeats count")
        let release = SystemHUDMediaKey(data1: (2 << 16) | (0xB << 8))
        #expect(release.brightnessPress == nil)
        let volumeUp = SystemHUDMediaKey(keyCode: SystemHUDMediaKey.soundUp, isKeyDown: true, isRepeat: false)
        #expect(volumeUp.brightnessPress == nil && !volumeUp.isBrightnessKey)

        for key in [up, heldDown, release] {
            #expect(!SystemHUDMediaKeyInterceptor.swallows(key, interceptingVolume: true))
            #expect(!SystemHUDMediaKeyInterceptor.swallows(key, interceptingVolume: false))
        }
        #expect(SystemHUDMediaKeyInterceptor.swallows(volumeUp, interceptingVolume: true))
        #expect(!SystemHUDMediaKeyInterceptor.swallows(volumeUp, interceptingVolume: false),
                "a tap kept only for brightness keys passes volume keys on too")
    }

    @Test
    func tapRetryBacksOffAfterTheFirstMinute() {
        #expect(SystemHUDTapRetryPolicy.interval(afterAttempt: 0) == .seconds(2))
        #expect(SystemHUDTapRetryPolicy.interval(afterAttempt: 29) == .seconds(2))
        #expect(SystemHUDTapRetryPolicy.interval(afterAttempt: 30) == .seconds(15))
        #expect(SystemHUDTapRetryPolicy.giveUpAfter == .seconds(3600))
    }

    // MARK: Audio snapshots

    @Test
    func snapshotsWithinToleranceAreTheSameLevel() {
        let base = SystemAudioSnapshot(deviceID: 42, volume: 0.5, isMuted: false, isBluetooth: false)
        var nudged = base
        nudged.volume = 0.5003
        #expect(SystemAudioDevice.isSameLevel(base, nudged))
        nudged.volume = 0.52
        #expect(!SystemAudioDevice.isSameLevel(base, nudged))
        var muted = base
        muted.isMuted = true
        #expect(!SystemAudioDevice.isSameLevel(base, muted))
        #expect(muted.displayLevel == 0)
        var otherDevice = base
        otherDevice.deviceID = 7
        #expect(!SystemAudioDevice.isSameLevel(base, otherDevice))
    }

    // MARK: Settings

    @Test
    func settingsDefaultToDesign() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        #expect(settings.enableSystemHUD)
        #expect(settings.style == .inline)
        #expect(settings.enableVolumeHUD)
        #expect(settings.interceptMediaKeys)
        #expect(settings.volumeStepPercent == 6)
        #expect(settings.volumeFineStepPercent == 2)
        #expect(!settings.playVolumeFeedback)
        #expect(settings.progressBarStyle == .hierarchical)
        #expect(settings.showPercentages)
        #expect(settings.colorCodedVolume)
        #expect(settings.smoothColorGradient)
        #expect(!settings.glowEffect)
        #expect(!settings.useAccentColor)
        #expect(settings.enableCapsLockIndicator)
        #expect(!settings.showCapsLockLabel)
        #expect(settings.capsLockTint == .white)
        #expect(abs(settings.volumeStep(fine: false) - 0.06) < 0.0001)
        #expect(abs(settings.volumeStep(fine: true) - 0.02) < 0.0001)
    }

    @Test
    func settingsPersistUnderFeaturePrefix() {
        let defaults = makeDefaults()
        let settings = SystemHUDSettings(defaults: defaults)
        settings.style = .standard
        settings.showCapsLockLabel = true
        settings.capsLockTint = .green
        settings.volumeStepPercent = 10
        settings.progressBarStyle = .segmented
        #expect(defaults.string(forKey: "systemHUD.style") == "standard")
        let reloaded = SystemHUDSettings(defaults: defaults)
        #expect(reloaded.style == .standard)
        #expect(reloaded.showCapsLockLabel)
        #expect(reloaded.capsLockTint == .green)
        #expect(reloaded.volumeStepPercent == 10)
        #expect(reloaded.progressBarStyle == .segmented)
    }

    @Test
    func choosingInlineStyleResetsGlowAndBarStyle() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        settings.style = .standard
        settings.glowEffect = true
        settings.progressBarStyle = .gradient
        settings.style = .inline
        #expect(!settings.glowEffect)
        #expect(settings.progressBarStyle == .hierarchical)
    }

    // MARK: Presenter

    @Test
    func inlineStyleShowsWingsInsteadOfSneakPeek() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        let center = IslandActivityCenter()
        var peeks: [SneakPeek] = []
        let subscription = center.sneakPeekRequests.sink { peeks.append($0) }
        defer { subscription.cancel() }
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: center)
        let activity = InlineHUDActivity(presenter: presenter)

        #expect(!activity.isActivityVisible)
        presenter.presentVolume(level: 0.4, isBluetooth: false)
        #expect(activity.isActivityVisible)
        #expect(presenter.kind == .volume)
        #expect(presenter.level == 0.4)
        #expect(peeks.isEmpty)
        presenter.hideInlineHUD()
        #expect(!activity.isActivityVisible)
    }

    @Test
    func standardStyleRequestsLevelSneakPeek() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        settings.style = .standard
        let center = IslandActivityCenter()
        var peeks: [SneakPeek] = []
        let subscription = center.sneakPeekRequests.sink { peeks.append($0) }
        defer { subscription.cancel() }
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: center)

        presenter.presentVolume(level: 0.7, isBluetooth: false)
        presenter.presentVolume(level: 0, isBluetooth: false)
        presenter.presentMicrophone(isMuted: true)
        #expect(!presenter.isShowingInlineHUD)
        #expect(peeks.count == 3)
        #expect(peeks[0].kind == .volume && peeks[0].level == 0.7 && peeks[0].systemImage == "speaker.wave.2.fill")
        #expect(peeks[1].level == nil && peeks[1].title == "muted" && peeks[1].systemImage == "speaker.slash.fill")
        #expect(peeks[2].title == "Mic muted" && peeks[2].systemImage == "mic.slash.fill")
        #expect(peeks.allSatisfy { $0.duration == .milliseconds(1_500) })
        #expect(SystemHUDStandardRow.handles(peeks[0]) && SystemHUDStandardRow.handles(peeks[2]))
    }

    @Test
    func standardStyleShowsBrightnessInTheLevelRow() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        settings.style = .standard
        let center = IslandActivityCenter()
        var peeks: [SneakPeek] = []
        let subscription = center.sneakPeekRequests.sink { peeks.append($0) }
        defer { subscription.cancel() }
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: center)

        presenter.presentBrightness(level: 0.3)
        presenter.presentBrightness(level: 0)
        #expect(!presenter.isShowingInlineHUD)
        #expect(peeks.count == 2)
        #expect(peeks.allSatisfy { $0.kind == .brightness && $0.systemImage == "sun.max.fill" })
        #expect(peeks.allSatisfy(SystemHUDStandardRow.handles), "drawn by the level row, like volume")
        #expect(peeks[0].level == 0.3)
        #expect(peeks[1].level == 0 && peeks[1].title == "Brightness", "zero is a level, not \"muted\"")
    }

    @Test
    func standardRowKeepsTheSpeakerOnBluetoothWhileInlineShowsHeadphones() {
        // The standard row always draws the speaker symbol; only the inline HUD
        // swaps in headphones for a Bluetooth route.
        let peek = SystemHUDPresenter.standardSneakPeek(kind: .volume, level: 0.5, isBluetooth: true)
        #expect(peek.systemImage == "speaker.wave.2.fill")
        #expect(peek.level == 0.5)
        let muted = SystemHUDPresenter.standardSneakPeek(kind: .volume, level: 0, isBluetooth: true)
        #expect(muted.systemImage == "speaker.slash.fill")
        #expect(SystemHUDPresenter.volumeSymbolName(for: 0.5, isBluetooth: true) == "headphones")
        #expect(!SystemHUDStandardRow.handles(SneakPeek(kind: .clipboard, systemImage: "doc", title: "Copied")))
    }

    @Test
    func capsLockMonitorStopsCleanlyAndReportsOff() {
        let caps = CapsLockFlag()
        caps.isOn = true
        let monitor = CapsLockMonitor(readState: { caps.isOn })
        monitor.start()
        #expect(monitor.isRunning && monitor.isCapsLockOn, "start reads the current flag")
        monitor.stop()
        #expect(!monitor.isRunning && !monitor.isCapsLockOn, "a stopped monitor reports Caps Lock off")
        monitor.start()
        #expect(monitor.isCapsLockOn)
        monitor.stop()
    }

    @Test
    func animationConstants() {
        #expect(SystemHUDPresenter.displayDuration == .milliseconds(1_500))
        #expect(CapsLockMonitor.pollInterval == .milliseconds(150))
        #expect(SystemHUDManager.feedbackInterval == .milliseconds(80))
        #expect(SystemHUDManager.systemVolumeFeedbackPath.hasSuffix("Media Keys.aif"))
    }

    @Test
    func gatesHonourSettingsLockAndSuppression() {
        let settings = SystemHUDSettings(defaults: makeDefaults())
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: IslandActivityCenter())

        settings.enableVolumeHUD = false
        presenter.presentVolume(level: 0.5, isBluetooth: false)
        #expect(!presenter.isShowingInlineHUD)
        settings.enableVolumeHUD = true

        settings.enableSystemHUD = false
        presenter.presentMicrophone(isMuted: false)
        #expect(!presenter.isShowingInlineHUD)
        settings.enableSystemHUD = true

        presenter.suppressVolumeHUD(for: 5)
        presenter.presentVolume(level: 0.5, isBluetooth: false)
        #expect(!presenter.isShowingInlineHUD)
        presenter.presentMicrophone(isMuted: false)
        #expect(presenter.isShowingInlineHUD, "suppression only covers volume")
        #expect(presenter.kind == .microphone && presenter.level == 1)

        presenter.isScreenLocked = true
        #expect(!presenter.isShowingInlineHUD, "locking hides the HUD")
        presenter.presentMicrophone(isMuted: true)
        #expect(!presenter.isShowingInlineHUD)
    }

    @Test
    func dragOnlyMovesTheVisibleVolumeHUD() {
        let presenter = SystemHUDPresenter(settings: SystemHUDSettings(defaults: makeDefaults()), activityCenter: IslandActivityCenter())
        presenter.userDidDrag(to: 0.9)
        #expect(presenter.level == 0)
        presenter.presentVolume(level: 0.2, isBluetooth: false)
        presenter.userDidDrag(to: 1.3)
        #expect(presenter.level == 1)
    }

    // MARK: Caps Lock

    @Test
    func capsLockActivityFollowsMonitorAndSettings() {
        let caps = CapsLockFlag()
        let monitor = CapsLockMonitor(readState: { caps.isOn })
        let settings = SystemHUDSettings(defaults: makeDefaults())
        let presenter = SystemHUDPresenter(settings: settings, activityCenter: IslandActivityCenter())
        let activity = CapsLockActivity(monitor: monitor, settings: settings, presenter: presenter)

        monitor.start()
        defer { monitor.stop() }
        #expect(!activity.isActivityVisible)
        caps.isOn = true
        monitor.poll()
        #expect(monitor.isCapsLockOn)
        #expect(activity.isActivityVisible)
        #expect(activity.priority == ClosedActivityPriority.capsLock)

        let ctx = context()
        #expect(activity.rightWingWidth(in: ctx) == 0)
        settings.showCapsLockLabel = true
        #expect(activity.rightWingWidth(in: ctx) == 86)
        #expect(activity.leftWingWidth(in: ctx) == 90)

        settings.enableCapsLockIndicator = false
        #expect(!activity.isActivityVisible)
        settings.enableCapsLockIndicator = true
        presenter.isScreenLocked = true
        #expect(!activity.isActivityVisible)
        presenter.isScreenLocked = false
        caps.isOn = false
        monitor.poll()
        #expect(!activity.isActivityVisible)
    }

    @Test
    func activityIdentityAndPriorityOrdering() {
        let presenter = SystemHUDPresenter(settings: SystemHUDSettings(defaults: makeDefaults()), activityCenter: IslandActivityCenter())
        let inline = InlineHUDActivity(presenter: presenter)
        #expect(inline.priority == ClosedActivityPriority.inlineHUD)
        #expect(inline.priority < ClosedActivityPriority.capsLock)
        #expect(inline.activityID != CapsLockActivity(presenter: presenter).activityID)
    }
}

/// Stand-in for the keyboard's Caps Lock flag.
@MainActor
private final class CapsLockFlag {
    var isOn = false
}
