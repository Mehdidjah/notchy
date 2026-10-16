import AppKit
import Combine
import CoreAudio
import Foundation

/// An audio output the system can route to.
struct MediaAudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    /// Atoll's glyph choice: named products first, then the transport.
    var iconName: String {
        Self.iconName(name: name, transportType: transportType)
    }

    static func iconName(name: String, transportType: UInt32) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods") { return "airpodspro" }
        if lowered.contains("macbook") { return "laptopcomputer" }
        if lowered.contains("headphone") || lowered.contains("headset") || lowered.contains("beats") { return "headphones" }
        if lowered.contains("homepod") { return "hifispeaker.2" }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth:
            return lowered.contains("speaker") ? "speaker.wave.2" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "tv"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeFireWire:
            return "hifispeaker.2"
        case kAudioDeviceTransportTypeBuiltIn:
            return lowered.contains("display") ? "tv" : "speaker.wave.2"
        default:
            return "speaker.wave.2"
        }
    }

    /// The default device first, the rest by name.
    static func sorted(_ devices: [MediaAudioOutputDevice], defaultID: AudioDeviceID) -> [MediaAudioOutputDevice] {
        devices.sorted { lhs, rhs in
            if lhs.id == defaultID { return rhs.id != defaultID }
            if rhs.id == defaultID { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Lists the system's audio outputs and switches the default one, through public CoreAudio.
/// Every HAL call runs on a private queue; the published list lives on the main actor.
@MainActor
final class MediaAudioRouteManager: ObservableObject {
    static let shared = MediaAudioRouteManager()

    @Published private(set) var devices: [MediaAudioOutputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = 0

    private let hal = MediaAudioHAL()
    private var isObserving = false

    init() {}

    var activeDevice: MediaAudioOutputDevice? {
        devices.first { $0.id == activeDeviceID }
    }

    /// Starts following device and default-output changes.
    func start() {
        guard !isObserving else { return }
        isObserving = true
        hal.observeChanges { [weak self] in
            Task { @MainActor in self?.refreshDevices() }
        }
        refreshDevices()
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        hal.stopObserving()
    }

    func refreshDevices() {
        let hal = hal
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = hal.readOutputs()
            await self?.apply(snapshot)
        }
    }

    func select(_ device: MediaAudioOutputDevice) {
        let hal = hal
        let id = device.id
        activeDeviceID = id
        Task.detached(priority: .userInitiated) { [weak self] in
            hal.setDefaultOutput(id)
            let snapshot = hal.readOutputs()
            await self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: MediaAudioHAL.Snapshot) {
        let sorted = MediaAudioOutputDevice.sorted(snapshot.devices, defaultID: snapshot.defaultID)
        if devices != sorted { devices = sorted }
        if activeDeviceID != snapshot.defaultID { activeDeviceID = snapshot.defaultID }
    }
}

/// The HAL side of `MediaAudioRouteManager`: stateless reads and writes plus the property
/// listeners, all on one serial queue.
final class MediaAudioHAL: @unchecked Sendable {
    struct Snapshot: Sendable {
        var devices: [MediaAudioOutputDevice]
        var defaultID: AudioDeviceID
    }

    private let queue = DispatchQueue(label: "NotchIsland.media.audio-route", qos: .userInitiated)
    /// Touched only on `queue`.
    private var listener: AudioObjectPropertyListenerBlock?

    private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard listener == nil else { return }
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            listener = block
            var devices = Self.devicesAddress
            var output = Self.defaultOutputAddress
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, block)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &output, queue, block)
        }
    }

    func stopObserving() {
        queue.async { [self] in
            guard let block = listener else { return }
            listener = nil
            var devices = Self.devicesAddress
            var output = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, queue, block)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &output, queue, block)
        }
    }

    func readOutputs() -> Snapshot {
        queue.sync {
            let defaultID = Self.defaultOutputID()
            let devices = Self.deviceIDs().compactMap(Self.outputDevice(for:))
            return Snapshot(devices: devices, defaultID: defaultID)
        }
    }

    func setDefaultOutput(_ id: AudioDeviceID) {
        queue.sync {
            var target = id
            var address = Self.defaultOutputAddress
            _ = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                UInt32(MemoryLayout<AudioDeviceID>.size), &target
            )
        }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func defaultOutputID() -> AudioDeviceID {
        var address = defaultOutputAddress
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : 0
    }

    private static func outputDevice(for id: AudioDeviceID) -> MediaAudioOutputDevice? {
        guard outputChannelCount(id) > 0 else { return nil }
        return MediaAudioOutputDevice(id: id, name: name(of: id) ?? "Unknown Device", transportType: transportType(of: id))
    }

    private static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var type = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type)
        return status == noErr ? type : kAudioDeviceTransportTypeUnknown
    }
}

// MARK: - AirPlay (Music)

/// An AirPlay receiver as Music reports it.
struct MediaAirPlayDevice: Identifiable, Equatable, Sendable {
    /// Network address, or the name when Music has none.
    let id: String
    let name: String
    let kind: String
    var isSelected: Bool
    /// 0...100.
    var volume: Int

    var iconName: String {
        switch kind {
        case "HomePod": return "homepodmini"
        case "AirPort Express": return "airport.express"
        case "computer": return "laptopcomputer"
        case "AirPlay device":
            let lowered = name.lowercased()
            if lowered.contains("tv") || lowered.contains("theatre") || lowered.contains("theater") { return "appletv" }
            return "airplayaudio"
        default:
            return "airplayaudio"
        }
    }
}

/// Music's AirPlay receivers: listing, (de)selecting and per-device volume, all through
/// Music's AppleScript dictionary.
@MainActor
final class MediaAirPlayManager: ObservableObject {
    static let shared = MediaAirPlayManager()

    @Published private(set) var devices: [MediaAirPlayDevice] = []
    @Published private(set) var isLoading = false

    private var isBusy = false
    /// The latest value each slider asked for, not yet sent.
    private var pendingVolume: [String: Int] = [:]
    private var committedVolume: [String: Int] = [:]
    private var commitTask: Task<Void, Never>?

    /// Sliders drain at this interval while dragged, so Music is never flooded.
    static let volumeCommitInterval: Duration = .milliseconds(150)

    init() {}

    func refreshDevices() async {
        guard !isBusy, MediaScripting.isRunning(.appleMusic) else { return }
        isBusy = true
        isLoading = true
        defer {
            isBusy = false
            isLoading = false
        }
        guard let fetched = await MediaAppleScript.evaluate(Self.listScript, cache: true, parse: Self.parseDevices)
        else { return }
        devices = fetched
        for device in fetched { committedVolume[device.id] = device.volume }
    }

    func toggle(_ device: MediaAirPlayDevice) async {
        guard !isBusy else { return }
        isBusy = true
        let script = """
        tell application "Music"
            try
                set targetDevice to first AirPlay device whose name is "\(Self.escaped(device.name))"
                set selected of targetDevice to \(!device.isSelected)
            end try
        end tell
        """
        await MediaAppleScript.run(script)
        try? await Task.sleep(for: .milliseconds(200))
        isBusy = false
        await refreshDevices()
    }

    func currentVolume(for id: String) -> Int {
        pendingVolume[id] ?? committedVolume[id] ?? devices.first { $0.id == id }?.volume ?? 0
    }

    /// Records the slider's value; a throttled loop sends the latest one every 150 ms.
    /// Nothing published changes here, so the slider is never rebuilt mid-drag.
    func setVolume(_ volume: Int, for id: String) {
        pendingVolume[id] = min(max(volume, 0), 100)
        guard commitTask == nil else { return }
        commitTask = Task { [weak self] in
            while let self, !Task.isCancelled, let entry = self.pendingVolume.first {
                self.pendingVolume[entry.key] = nil
                await self.commit(entry.value, for: entry.key)
                try? await Task.sleep(for: Self.volumeCommitInterval)
            }
            self?.commitTask = nil
        }
    }

    /// Music rebalances the other receivers when one drops past another in a single step,
    /// so a fall through a louder receiver's level stops at that level first.
    private func commit(_ volume: Int, for id: String) async {
        guard let device = devices.first(where: { $0.id == id }) else { return }
        let current = committedVolume[id] ?? volume
        let loudestOther = devices
            .filter { $0.id != id && $0.isSelected }
            .map { committedVolume[$0.id] ?? $0.volume }
            .max() ?? 0
        for step in Self.volumeSteps(from: current, to: volume, loudestOther: loudestOther) {
            await MediaAppleScript.run("""
            tell application "Music"
                try
                    set sound volume of (first AirPlay device whose name is "\(Self.escaped(device.name))") to \(step)
                end try
            end tell
            """)
        }
        committedVolume[id] = volume
    }

    /// The values to send to move from `current` to `target` without crossing below the
    /// loudest other selected receiver in one step.
    nonisolated static func volumeSteps(from current: Int, to target: Int, loudestOther: Int) -> [Int] {
        if loudestOther > 0, current > loudestOther, target < loudestOther {
            return [loudestOther, target]
        }
        return [target]
    }

    nonisolated static func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func parseDevices(_ descriptor: NSAppleEventDescriptor) -> [MediaAirPlayDevice]? {
        guard descriptor.numberOfItems > 0 else { return [] }
        var devices: [MediaAirPlayDevice] = []
        for index in 1 ... descriptor.numberOfItems {
            guard let item = descriptor.atIndex(index), item.numberOfItems >= 5 else { continue }
            let name = item.atIndex(1)?.stringValue ?? "Unknown"
            let address = item.atIndex(4)?.stringValue ?? ""
            devices.append(MediaAirPlayDevice(
                id: address.isEmpty ? name : address,
                name: name,
                kind: item.atIndex(2)?.stringValue ?? "AirPlay device",
                isSelected: item.atIndex(3)?.booleanValue ?? false,
                volume: Int(item.atIndex(5)?.int32Value ?? 50)
            ))
        }
        return devices
    }

    private static let listScript = """
    tell application "Music"
        with timeout of 4 seconds
            try
                set deviceList to {}
                repeat with receiver in AirPlay devices
                    set end of deviceList to {name of receiver, (kind of receiver) as string, selected of receiver, network address of receiver, sound volume of receiver}
                end repeat
                return deviceList
            on error
                return {}
            end try
        end timeout
    end tell
    """
}
