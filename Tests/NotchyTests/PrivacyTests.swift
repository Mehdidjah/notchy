import Combine
import Foundation
import Testing
@testable import Notchy

@MainActor
struct PrivacyTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "PrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func context(height: CGFloat = 32, hovering: Bool = false, gesture: CGFloat = 0) -> ClosedActivityContext {
        ClosedActivityContext(
            closedHeight: height,
            notchWidth: 185,
            isHovering: hovering,
            gestureProgress: gesture,
            hasHardwareNotch: true
        )
    }

    // MARK: Layout of the eight combinations

    @Test
    func singleDeviceSitsAloneInTheRightWing() {
        let camera = PrivacyIndicatorState(camera: true, microphone: false, screenRecording: false)
        #expect(camera.leftContent == .empty)
        #expect(camera.rightIndicators == [.camera])

        let microphone = PrivacyIndicatorState(camera: false, microphone: true, screenRecording: false)
        #expect(microphone.leftContent == .empty)
        #expect(microphone.rightIndicators == [.microphone])
    }

    @Test
    func bothDevicesSplitMicrophoneLeftCameraRight() {
        let both = PrivacyIndicatorState(camera: true, microphone: true, screenRecording: false)
        #expect(both.leftContent == .microphone)
        #expect(both.rightIndicators == [.camera])
    }

    @Test
    func recordingTakesTheLeftWingAndPushesBothGlyphsRight() {
        let all = PrivacyIndicatorState(camera: true, microphone: true, screenRecording: true)
        #expect(all.leftContent == .recordingBadge)
        #expect(all.rightIndicators == [.microphone, .camera])

        let recordingOnly = PrivacyIndicatorState(camera: false, microphone: false, screenRecording: true)
        #expect(recordingOnly.leftContent == .recordingBadge)
        #expect(recordingOnly.rightIndicators.isEmpty)
        #expect(recordingOnly.hasAnyIndicator)
        #expect(!PrivacyIndicatorState.none.hasAnyIndicator)
    }

    @Test
    func wingsAreTheSquareWingPlusTwentyPoints() {
        let closed = context()
        let single = PrivacyIndicatorState(camera: true, microphone: false, screenRecording: false)
        #expect(single.leftWingWidth(in: closed) == 0)
        #expect(single.rightWingWidth(in: closed) == 40, "32 - 12 = 20 content height, + 20")

        let both = PrivacyIndicatorState(camera: true, microphone: true, screenRecording: false)
        #expect(both.leftWingWidth(in: closed) == 40)

        // The privacy view never sees hover or swipe: its wings stay put.
        let hovered = context(hovering: true, gesture: 10)
        #expect(single.rightWingWidth(in: hovered) == 40, "hover and swipe do not widen the wings")
        #expect(both.leftWingWidth(in: hovered) == 40)
    }

    @Test
    func indicatorColoursMatchTheSystemIndicators() {
        #expect(PrivacyIndicatorKind.camera.systemImage == "video.fill")
        #expect(PrivacyIndicatorKind.microphone.systemImage == "mic.fill")
    }

    // MARK: Microphone combination rule

    @Test
    func inputOnlyDeviceRunningMeansCapture() {
        let devices = [MicrophoneDeviceReading(isRunning: true, hasOutputStreams: false)]
        #expect(MicrophoneUsageMonitor.isCapturing(devices: devices, processesCapturing: false))
    }

    @Test
    func sharedDevicePlayingMusicIsNotCapture() {
        let headset = [MicrophoneDeviceReading(isRunning: true, hasOutputStreams: true)]
        #expect(!MicrophoneUsageMonitor.isCapturing(devices: headset, processesCapturing: false))
        #expect(MicrophoneUsageMonitor.isCapturing(devices: headset, processesCapturing: true))
        #expect(MicrophoneUsageMonitor.isCapturing(devices: headset, processesCapturing: nil),
                "without process information the device signal stands")
    }

    @Test
    func idleDevicesAreNotCapture() {
        let devices = [
            MicrophoneDeviceReading(isRunning: false, hasOutputStreams: false),
            MicrophoneDeviceReading(isRunning: false, hasOutputStreams: true)
        ]
        #expect(!MicrophoneUsageMonitor.isCapturing(devices: devices, processesCapturing: true))
    }

    // MARK: Settings and monitor

    @Test
    func settingsDefaultOnAndPersist() {
        let defaults = makeDefaults()
        let settings = PrivacySettings(defaults: defaults)
        #expect(settings.enableCameraDetection)
        #expect(settings.enableMicrophoneDetection)
        settings.enableCameraDetection = false
        #expect(defaults.object(forKey: "privacy.enableCameraDetection") as? Bool == false)
        #expect(!PrivacySettings(defaults: defaults).enableCameraDetection)
    }

    @Test
    func monitorAppliesTheDetectionSwitches() {
        let settings = PrivacySettings(defaults: makeDefaults())
        let monitor = PrivacyMonitor(settings: settings, usesHardware: false)
        monitor.setCameraInUse(true)
        monitor.setMicrophoneInUse(true)
        #expect(monitor.indicators == PrivacyIndicatorState(camera: true, microphone: true, screenRecording: false))

        settings.enableMicrophoneDetection = false
        #expect(monitor.indicators == PrivacyIndicatorState(camera: true, microphone: false, screenRecording: false))

        monitor.setCameraInUse(false)
        #expect(!monitor.indicators.hasAnyIndicator)
    }

    @Test
    func activityShowsWhileAnythingIsLiveAndReportsChanges() {
        let settings = PrivacySettings(defaults: makeDefaults())
        let monitor = PrivacyMonitor(settings: settings, usesHardware: false)
        let activity = PrivacyActivity(monitor: monitor)
        var notifications = 0
        let token = activity.activityDidChange.sink { notifications += 1 }
        defer { token.cancel() }

        #expect(activity.activityID == "privacy")
        #expect(activity.priority == ClosedActivityPriority.privacy)
        #expect(!activity.isActivityVisible)

        monitor.setCameraInUse(true)
        #expect(activity.isActivityVisible)
        #expect(notifications == 1)
        #expect(activity.leftWingWidth(in: context()) == 0)

        monitor.setMicrophoneInUse(true)
        #expect(notifications == 2, "the left wing appearing changes the widths")
        #expect(activity.leftWingWidth(in: context()) == 40)

        monitor.setMicrophoneInUse(false)
        monitor.setCameraInUse(false)
        #expect(!activity.isActivityVisible)
        #expect(notifications == 4)
    }

    @Test
    func activityHidesWhenBothDetectorsAreOff() {
        let settings = PrivacySettings(defaults: makeDefaults())
        let monitor = PrivacyMonitor(settings: settings, usesHardware: false)
        let activity = PrivacyActivity(monitor: monitor)
        monitor.setScreenRecordingActive(true)
        #expect(activity.isActivityVisible)
        settings.enableCameraDetection = false
        settings.enableMicrophoneDetection = false
        #expect(!activity.isActivityVisible, "the activity is only offered while a detector is on")
    }
}
