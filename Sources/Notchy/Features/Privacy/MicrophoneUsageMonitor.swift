import CoreAudio
import Foundation

/// Reports whether any process is capturing audio input.
///
/// The primary signal is Atoll's: `kAudioDevicePropertyDeviceIsRunningSomewhere` on input
/// devices. Atoll watches only the default input device captured at launch; this watches every
/// device that has input streams and re-subscribes when devices or the default input change.
///
/// A device with both input and output streams (AirPods, USB headsets, virtual meeting
/// devices) also "runs" when it is only playing sound, which would light the microphone glyph
/// for music. For those devices the answer is confirmed with the per-process
/// `kAudioProcessPropertyIsRunningInput` flag (macOS 14); when the process list cannot be read
/// the device signal is used as is.
final class MicrophoneUsageMonitor: @unchecked Sendable {
    typealias ChangeHandler = @Sendable (Bool) -> Void

    private let queue = DispatchQueue(label: "Notchy.Privacy.MicrophoneUsage", qos: .utility)

    // Everything below is confined to `queue`.
    private var handler: ChangeHandler?
    private var isRunning = false
    private var lastReported: Bool?
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var systemListeners: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]

    init() {}

    func start(onChange: @escaping ChangeHandler) {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            handler = onChange
            lastReported = nil
            installSystemListeners()
            resubscribeDevices()
            resubscribeProcesses()
            evaluate()
        }
    }

    func stop() {
        queue.async { [self] in
            guard isRunning else { return }
            isRunning = false
            removeAllListeners()
            handler = nil
            lastReported = nil
        }
    }

    func refresh() {
        queue.async { [self] in
            guard isRunning else { return }
            evaluate()
        }
    }

    // MARK: - Listeners

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func installSystemListeners() {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyProcessObjectList
        ]
        for selector in selectors where systemListeners[selector] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.isRunning else { return }
                if selector == kAudioHardwarePropertyProcessObjectList {
                    self.resubscribeProcesses()
                } else {
                    self.resubscribeDevices()
                }
                self.evaluate()
            }
            var address = Self.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            )
            if status == noErr {
                systemListeners[selector] = block
            }
        }
    }

    private func resubscribeDevices() {
        let current = Set(Self.inputDevices())
        for (device, block) in deviceListeners where !current.contains(device) {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            _ = AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
            deviceListeners[device] = nil
        }
        for device in current where deviceListeners[device] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.isRunning else { return }
                self.evaluate()
            }
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                deviceListeners[device] = block
            }
        }
    }

    private func resubscribeProcesses() {
        let current = Set(Self.processObjects() ?? [])
        for (process, block) in processListeners where !current.contains(process) {
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            _ = AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
            processListeners[process] = nil
        }
        for process in current where processListeners[process] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.isRunning else { return }
                self.evaluate()
            }
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            if AudioObjectAddPropertyListenerBlock(process, &address, queue, block) == noErr {
                processListeners[process] = block
            }
        }
    }

    private func removeAllListeners() {
        for (device, block) in deviceListeners {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            _ = AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
        }
        deviceListeners.removeAll()
        for (process, block) in processListeners {
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            _ = AudioObjectRemovePropertyListenerBlock(process, &address, queue, block)
        }
        processListeners.removeAll()
        for (selector, block) in systemListeners {
            var address = Self.address(selector)
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            )
        }
        systemListeners.removeAll()
    }

    // MARK: - Reading

    private func evaluate() {
        let active = Self.isCapturing(
            devices: deviceListeners.keys.map { device in
                MicrophoneDeviceReading(
                    isRunning: Self.uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0,
                    hasOutputStreams: Self.hasStreams(device, scope: kAudioObjectPropertyScopeOutput)
                )
            },
            processesCapturing: Self.anyProcessRunningInput()
        )
        guard active != lastReported else { return }
        lastReported = active
        handler?(active)
    }

    /// Combines device and process readings into one answer. Input-only devices are trusted
    /// outright; a running input+output device needs a process with live input, unless the
    /// process list is unavailable (`processesCapturing == nil`).
    static func isCapturing(devices: [MicrophoneDeviceReading], processesCapturing: Bool?) -> Bool {
        let running = devices.filter(\.isRunning)
        if running.contains(where: { !$0.hasOutputStreams }) { return true }
        guard !running.isEmpty else { return false }
        return processesCapturing ?? true
    }

    private static func inputDevices() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        let filled = Int(size) / MemoryLayout<AudioObjectID>.size
        return devices.prefix(filled).filter { hasStreams($0, scope: kAudioObjectPropertyScopeInput) }
    }

    /// Audio process objects, or nil when the system does not offer them.
    private static func processObjects() -> [AudioObjectID]? {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectHasProperty(system, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }
        return Array(processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func anyProcessRunningInput() -> Bool? {
        guard let processes = processObjects() else { return nil }
        return processes.contains { uint32($0, kAudioProcessPropertyIsRunningInput) != 0 }
    }

    private static func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}

/// One input device's state, as `MicrophoneUsageMonitor.isCapturing` weighs it.
struct MicrophoneDeviceReading: Equatable, Sendable {
    var isRunning: Bool
    var hasOutputStreams: Bool
}
