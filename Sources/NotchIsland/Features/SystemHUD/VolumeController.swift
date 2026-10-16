import Combine
import CoreAudio
import Foundation

/// A level change worth telling the HUD about.
struct SystemAudioChange: Equatable, Sendable {
    var snapshot: SystemAudioSnapshot
    var reason: SystemAudioChangeReason
}

/// The default output device's volume and mute flag, through public CoreAudio.
///
/// Mirrors the published state of the device on the main actor; every read and write runs on
/// `SystemAudioDevice`'s own queue. Other features (for example a music player's volume
/// slider) can drive volume through `setVolume(_:)` and should call
/// `SystemHUDPresenter.shared.suppressVolumeHUD(for:)` first, as Atoll's own sliders do.
@MainActor
final class VolumeController: ObservableObject {
    static let shared = VolumeController()

    /// 0...1, the device's level even while muted.
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    /// Bluetooth or Bluetooth LE output; the HUD then shows headphones like Atoll.
    @Published private(set) var isBluetoothOutput = false
    /// False until the device has answered once.
    @Published private(set) var hasReading = false
    @Published private(set) var isRunning = false

    /// Every published level change, including the reason it happened.
    let changes = PassthroughSubject<SystemAudioChange, Never>()

    private let device = SystemAudioDevice(direction: .output)

    init() {}

    /// Level shown by a HUD: zero while muted.
    var displayLevel: CGFloat { isMuted ? 0 : CGFloat(volume) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        device.start { [weak self] snapshot, reason in
            Task { @MainActor in self?.apply(snapshot, reason: reason) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        device.stop()
    }

    /// Moves the level by a signed fraction of the full range; unmutes first.
    func adjust(by delta: Float) {
        guard isRunning, delta != 0 else { return }
        device.adjustVolume(by: delta)
    }

    func setVolume(_ value: Float) {
        guard isRunning else { return }
        // Reflect the drag right away; the device confirms asynchronously.
        volume = SystemAudioDevice.clamp(value)
        isMuted = value <= SystemAudioDevice.silenceThreshold
        device.setVolume(value)
    }

    func toggleMute() {
        guard isRunning else { return }
        device.toggleMute()
    }

    func setMuted(_ muted: Bool) {
        guard isRunning else { return }
        device.setMuted(muted)
    }

    private func apply(_ snapshot: SystemAudioSnapshot, reason: SystemAudioChangeReason) {
        guard isRunning else { return }
        if let level = snapshot.volume {
            if volume != level { volume = level }
            if !hasReading { hasReading = true }
        }
        if isMuted != snapshot.isMuted { isMuted = snapshot.isMuted }
        if isBluetoothOutput != snapshot.isBluetooth { isBluetoothOutput = snapshot.isBluetooth }
        changes.send(SystemAudioChange(snapshot: snapshot, reason: reason))
    }
}

/// The default input device's mute flag, for Atoll's "Mic" HUD.
@MainActor
final class MicrophoneMuteMonitor: ObservableObject {
    static let shared = MicrophoneMuteMonitor()

    @Published private(set) var isMuted = false
    @Published private(set) var isRunning = false

    /// Emits the new mute state when it flips on the same device (not on a route change).
    let muteChanges = PassthroughSubject<Bool, Never>()

    private let device = SystemAudioDevice(direction: .input)

    init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        device.start { [weak self] snapshot, reason in
            Task { @MainActor in self?.apply(snapshot, reason: reason) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        device.stop()
    }

    func toggleMute() {
        guard isRunning else { return }
        device.toggleMute()
    }

    private func apply(_ snapshot: SystemAudioSnapshot, reason: SystemAudioChangeReason) {
        guard isRunning else { return }
        let changed = isMuted != snapshot.isMuted
        if changed { isMuted = snapshot.isMuted }
        switch reason {
        case .external, .command:
            if changed { muteChanges.send(snapshot.isMuted) }
        case .initial, .routeChanged:
            break
        }
    }
}
