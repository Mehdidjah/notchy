import AudioToolbox
import CoreAudio
import Foundation

/// What a default audio device reported at one moment.
struct SystemAudioSnapshot: Equatable, Sendable {
    var deviceID: AudioObjectID
    /// 0...1, or nil when the device publishes no readable level and none was ever read.
    var volume: Float?
    var isMuted: Bool
    /// True for Bluetooth and Bluetooth LE outputs (Atoll swaps the speaker for headphones).
    var isBluetooth: Bool

    /// The level a HUD shows: zero while muted, as in Atoll.
    var displayLevel: Float { isMuted ? 0 : (volume ?? 0) }
}

/// Why a snapshot was published.
enum SystemAudioChangeReason: Sendable, Equatable {
    /// First reading after `start`; never shown as a HUD.
    case initial
    /// Something outside this module changed the level or mute flag.
    case external
    /// The default device changed.
    case routeChanged
    /// This module wrote the level (a key press or a drag); always published, even when the
    /// value is pinned at a limit, so the HUD still answers the key.
    case command
}

/// Follows the default output or input device through public CoreAudio property listeners
/// and reads or writes its level and mute flag.
///
/// Every stored property is confined to `queue`: the listener blocks are scheduled on it and
/// each public method hops onto it, so property reads and writes never run on the main thread
/// (a Bluetooth device can take a while to answer).
final class SystemAudioDevice: @unchecked Sendable {
    enum Direction: Sendable {
        case output
        case input
    }

    typealias Handler = @Sendable (SystemAudioSnapshot, SystemAudioChangeReason) -> Void

    let direction: Direction
    private let queue: DispatchQueue

    private var handler: Handler?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var lastPublished: SystemAudioSnapshot?
    /// Last level each device answered with, so a failed read holds the level instead of
    /// reporting silence (Atoll's per-device volume memory).
    private var knownVolumes: [AudioObjectID: Float] = [:]
    /// A listener can fire once per channel for one change; these are coalesced.
    private var pendingExternalRead = false

    /// Below this a level counts as silence and the device is muted (Atoll: 0.001).
    static let silenceThreshold: Float = 0.001
    /// Smaller differences are treated as the same level when deduplicating listener calls.
    static let changeTolerance: Float = 0.0005

    init(direction: Direction) {
        self.direction = direction
        let name = direction == .output ? "output" : "input"
        queue = DispatchQueue(label: "com.notchisland.systemhud.audio.\(name)", qos: .userInitiated)
    }

    // MARK: Lifecycle

    func start(handler: @escaping Handler) {
        queue.async { [self] in
            self.handler = handler
            installDefaultDeviceListener()
            attach(to: resolveDefaultDevice())
            publish(reason: .initial, force: true)
        }
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            removeDeviceListeners()
            removeDefaultDeviceListener()
            deviceID = AudioObjectID(kAudioObjectUnknown)
            lastPublished = nil
        }
    }

    // MARK: Commands

    /// Moves the level by `delta`, unmuting first, the way Atoll's volume keys do.
    func adjustVolume(by delta: Float) {
        queue.async { [self] in
            let device = deviceID
            guard device != kAudioObjectUnknown else { return }
            if readMute(on: device) == true { writeMute(false, on: device) }
            // A relative step needs a level that was really read from this device.
            guard let current = readVolume(on: device) ?? knownVolumes[device] else {
                publish(reason: .command, force: true)
                return
            }
            writeVolume(Self.clamp(current + delta), on: device)
            publish(reason: .command, force: true)
        }
    }

    func setVolume(_ value: Float) {
        queue.async { [self] in
            let device = deviceID
            guard device != kAudioObjectUnknown else { return }
            writeVolume(Self.clamp(value), on: device)
            publish(reason: .command, force: true)
        }
    }

    func toggleMute() {
        queue.async { [self] in
            let device = deviceID
            guard device != kAudioObjectUnknown else { return }
            let muted = readMute(on: device) ?? false
            writeMute(!muted, on: device)
            publish(reason: .command, force: true)
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async { [self] in
            let device = deviceID
            guard device != kAudioObjectUnknown else { return }
            writeMute(muted, on: device)
            publish(reason: .command, force: true)
        }
    }

    // MARK: Listeners (queue-confined)

    private var scope: AudioObjectPropertyScope {
        direction == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }

    private var defaultDeviceSelector: AudioObjectPropertySelector {
        direction == .output
            ? kAudioHardwarePropertyDefaultOutputDevice
            : kAudioHardwarePropertyDefaultInputDevice
    }

    private func installDefaultDeviceListener() {
        guard defaultDeviceListener == nil else { return }
        var address = CoreAudioProperty.address(defaultDeviceSelector, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultDeviceChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block
        )
        if status == noErr { defaultDeviceListener = block }
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListener else { return }
        var address = CoreAudioProperty.address(defaultDeviceSelector, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        defaultDeviceListener = nil
    }

    private func handleDefaultDeviceChange() {
        guard handler != nil else { return }
        let newDevice = resolveDefaultDevice()
        guard newDevice != deviceID else { return }
        attach(to: newDevice)
        publish(reason: .routeChanged, force: true)
    }

    private func attach(to device: AudioObjectID) {
        removeDeviceListeners()
        deviceID = device
        guard device != kAudioObjectUnknown else { return }

        var selectors: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = []
        if direction == .output {
            selectors.append((kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain))
            selectors.append(contentsOf: volumeElements(on: device).map { (kAudioDevicePropertyVolumeScalar, $0) })
        }
        selectors.append(contentsOf: muteElements(on: device).map { (kAudioDevicePropertyMute, $0) })

        for (selector, element) in selectors {
            var address = CoreAudioProperty.address(selector, scope: scope, element: element)
            guard CoreAudioProperty.has(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.scheduleExternalRead()
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for listener in deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, listener.block)
        }
        deviceListeners.removeAll()
    }

    /// Coalesces the burst of per-channel callbacks one change produces into a single read.
    private func scheduleExternalRead() {
        guard handler != nil, !pendingExternalRead else { return }
        pendingExternalRead = true
        queue.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
            guard let self else { return }
            self.pendingExternalRead = false
            self.publish(reason: .external, force: false)
        }
    }

    private func publish(reason: SystemAudioChangeReason, force: Bool) {
        guard let handler, deviceID != kAudioObjectUnknown else { return }
        let device = deviceID
        let snapshot = SystemAudioSnapshot(
            deviceID: device,
            volume: direction == .output ? (readVolume(on: device) ?? knownVolumes[device]) : nil,
            isMuted: readMute(on: device) ?? false,
            isBluetooth: CoreAudioProperty.isBluetooth(device)
        )
        if direction == .output, snapshot.volume == nil, reason != .initial { return }
        if !force, let lastPublished, Self.isSameLevel(lastPublished, snapshot) { return }
        lastPublished = snapshot
        handler(snapshot, reason)
    }

    static func isSameLevel(_ lhs: SystemAudioSnapshot, _ rhs: SystemAudioSnapshot) -> Bool {
        guard lhs.deviceID == rhs.deviceID, lhs.isMuted == rhs.isMuted else { return false }
        switch (lhs.volume, rhs.volume) {
        case let (left?, right?): return abs(left - right) <= changeTolerance
        case (nil, nil): return true
        default: return false
        }
    }

    // MARK: Property access (queue-confined)

    private func resolveDefaultDevice() -> AudioObjectID {
        var address = CoreAudioProperty.address(defaultDeviceSelector, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    /// Main element first, then the first two channels, as Atoll probes them.
    private static let candidateElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    private func volumeElements(on device: AudioObjectID) -> [AudioObjectPropertyElement] {
        elements(kAudioDevicePropertyVolumeScalar, on: device)
    }

    private func muteElements(on device: AudioObjectID) -> [AudioObjectPropertyElement] {
        elements(kAudioDevicePropertyMute, on: device)
    }

    /// The main element when the device has one, otherwise whichever channels it has.
    private func elements(_ selector: AudioObjectPropertySelector, on device: AudioObjectID) -> [AudioObjectPropertyElement] {
        let present = Self.candidateElements.filter { element in
            var address = CoreAudioProperty.address(selector, scope: scope, element: element)
            return CoreAudioProperty.has(device, &address)
        }
        if present.contains(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return present
    }

    /// The level macOS's own volume UI works through (virtual main volume), falling back to
    /// the per-channel scalar. Remembers what it read.
    private func readVolume(on device: AudioObjectID) -> Float? {
        var value: Float?
        var virtualAddress = CoreAudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)
        if CoreAudioProperty.has(device, &virtualAddress) {
            value = CoreAudioProperty.readFloat(device, &virtualAddress)
        }
        if value == nil {
            let readings = volumeElements(on: device).compactMap { element -> Float? in
                var address = CoreAudioProperty.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
                return CoreAudioProperty.readFloat(device, &address)
            }
            if !readings.isEmpty { value = readings.reduce(0, +) / Float(readings.count) }
        }
        if let value { knownVolumes[device] = Self.clamp(value) }
        return value.map(Self.clamp)
    }

    private func writeVolume(_ value: Float, on device: AudioObjectID) {
        // Atoll mutes at silence and unmutes above it.
        let muted = readMute(on: device) ?? false
        if value <= Self.silenceThreshold {
            if !muted { writeMute(true, on: device) }
        } else if muted {
            writeMute(false, on: device)
        }

        var wrote = false
        var virtualAddress = CoreAudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)
        if CoreAudioProperty.isSettable(device, &virtualAddress) {
            wrote = CoreAudioProperty.writeFloat(value, device, &virtualAddress)
        }
        if !wrote {
            for element in volumeElements(on: device) {
                var address = CoreAudioProperty.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
                if CoreAudioProperty.isSettable(device, &address), CoreAudioProperty.writeFloat(value, device, &address) {
                    wrote = true
                }
            }
        }
        if wrote { knownVolumes[device] = value }
    }

    /// True only when every mute element that answered is muted.
    private func readMute(on device: AudioObjectID) -> Bool? {
        let readings = muteElements(on: device).compactMap { element -> Bool? in
            var address = CoreAudioProperty.address(kAudioDevicePropertyMute, scope: scope, element: element)
            return CoreAudioProperty.readUInt32(device, &address).map { $0 != 0 }
        }
        guard !readings.isEmpty else { return nil }
        return readings.allSatisfy { $0 }
    }

    private func writeMute(_ muted: Bool, on device: AudioObjectID) {
        for element in muteElements(on: device) {
            var address = CoreAudioProperty.address(kAudioDevicePropertyMute, scope: scope, element: element)
            if CoreAudioProperty.isSettable(device, &address) {
                _ = CoreAudioProperty.writeUInt32(muted ? 1 : 0, device, &address)
            }
        }
    }

    static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

/// Thin wrappers over the public `AudioObject*` property calls.
enum CoreAudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard has(object, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func readFloat(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func writeFloat(_ value: Float, _ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var data = Float32(value)
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &data) == noErr
    }

    static func readUInt32(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func writeUInt32(_ value: UInt32, _ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var data = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &data) == noErr
    }

    static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        guard has(device, &address), let transport = readUInt32(device, &address) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
