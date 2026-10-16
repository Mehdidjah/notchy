import AppKit
import Combine
import SwiftUI

/// Combines the camera and microphone detectors (and an optional screen-recording source) into
/// the single state the privacy live activity draws, the way Atoll's PrivacyIndicatorManager does.
///
/// Detectors only run while their setting is on; switching one off hides its glyph at once.
@MainActor
final class PrivacyMonitor: ObservableObject {
    static let shared = PrivacyMonitor()

    /// Raw detector readings, before the user's switches are applied.
    @Published private(set) var cameraInUse = false
    @Published private(set) var microphoneInUse = false
    /// macOS has no public "the screen is being captured" signal, so this stays false unless
    /// another module that can tell sets it through `setScreenRecordingActive(_:)`.
    @Published private(set) var screenRecordingActive = false
    @Published private(set) var isMonitoring = false
    /// What the activity shows: readings filtered through the settings.
    @Published private(set) var indicators: PrivacyIndicatorState = .none

    let settings: PrivacySettings
    private let camera: CameraUsageMonitor?
    private let microphone: MicrophoneUsageMonitor?
    private var cancellables: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?

    /// - Parameter usesHardware: false builds a monitor that never touches CoreMediaIO or
    ///   CoreAudio, for tests that drive readings by hand.
    init(settings: PrivacySettings = .shared, usesHardware: Bool = true) {
        self.settings = settings
        camera = usesHardware ? CameraUsageMonitor() : nil
        microphone = usesHardware ? MicrophoneUsageMonitor() : nil

        settings.$enableCameraDetection
            .dropFirst()
            .sink { [weak self] enabled in self?.cameraSettingChanged(enabled) }
            .store(in: &cancellables)
        settings.$enableMicrophoneDetection
            .dropFirst()
            .sink { [weak self] enabled in self?.microphoneSettingChanged(enabled) }
            .store(in: &cancellables)
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        if settings.enableCameraDetection { startCamera() }
        if settings.enableMicrophoneDetection { startMicrophone() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.camera?.refresh()
                self?.microphone?.refresh()
            }
        }
        recompute()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        camera?.stop()
        microphone?.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        cameraInUse = false
        microphoneInUse = false
        recompute()
    }

    // MARK: - Readings

    func setCameraInUse(_ active: Bool) {
        guard cameraInUse != active else { return }
        cameraInUse = active
        recompute()
    }

    func setMicrophoneInUse(_ active: Bool) {
        guard microphoneInUse != active else { return }
        microphoneInUse = active
        recompute()
    }

    /// Hook for a screen-recording detector; the left wing then shows Atoll's red pulsing badge.
    func setScreenRecordingActive(_ active: Bool) {
        guard screenRecordingActive != active else { return }
        screenRecordingActive = active
        recompute()
    }

    /// Rebuilds `indicators`. Settings sinks pass the new switch value because `@Published`
    /// announces a change before the stored value is updated.
    private func recompute(cameraEnabled: Bool? = nil, microphoneEnabled: Bool? = nil) {
        let next = PrivacyIndicatorState(
            camera: cameraInUse && (cameraEnabled ?? settings.enableCameraDetection),
            microphone: microphoneInUse && (microphoneEnabled ?? settings.enableMicrophoneDetection),
            screenRecording: screenRecordingActive
        )
        guard next != indicators else { return }
        withAnimation(.smooth) { indicators = next }
    }

    // MARK: - Detectors

    private func startCamera() {
        camera?.start { [weak self] active in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.setCameraInUse(active) }
            }
        }
    }

    private func startMicrophone() {
        microphone?.start { [weak self] active in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.setMicrophoneInUse(active) }
            }
        }
    }

    private func cameraSettingChanged(_ enabled: Bool) {
        if isMonitoring {
            if enabled {
                startCamera()
            } else {
                camera?.stop()
                cameraInUse = false
            }
        }
        recompute(cameraEnabled: enabled)
    }

    private func microphoneSettingChanged(_ enabled: Bool) {
        if isMonitoring {
            if enabled {
                startMicrophone()
            } else {
                microphone?.stop()
                microphoneInUse = false
            }
        }
        recompute(microphoneEnabled: enabled)
    }
}
