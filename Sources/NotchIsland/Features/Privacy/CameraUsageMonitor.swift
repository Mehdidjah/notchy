import AVFoundation
import CoreMediaIO
import Foundation

/// Reports whether any process is running a camera.
///
/// Every CoreMediaIO device with input streams gets a listener on
/// `kCMIODevicePropertyDeviceIsRunningSomewhere`; the device list itself is watched so cameras
/// plugged in later are covered too. Each change re-reads the property on every device and ORs
/// the result with `AVCaptureDevice.isInUseByAnotherApplication`, the way Atoll combines both.
/// Everything runs on a private serial queue; results are handed to `onChange`, deduplicated.
final class CameraUsageMonitor: @unchecked Sendable {
    typealias ChangeHandler = @Sendable (Bool) -> Void

    private let queue = DispatchQueue(label: "NotchIsland.Privacy.CameraUsage", qos: .utility)

    // Everything below is confined to `queue`.
    private var handler: ChangeHandler?
    private var isRunning = false
    private var lastReported: Bool?
    private var deviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var deviceListListener: CMIOObjectPropertyListenerBlock?

    init() {}

    func start(onChange: @escaping ChangeHandler) {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            handler = onChange
            lastReported = nil
            installDeviceListListener()
            resubscribeDevices()
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

    /// Forces a fresh read, for example after the Mac wakes.
    func refresh() {
        queue.async { [self] in
            guard isRunning else { return }
            evaluate()
        }
    }

    // MARK: - Listeners

    private static var runningAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
    }

    private static var devicesAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private func installDeviceListListener() {
        guard deviceListListener == nil else { return }
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            self.resubscribeDevices()
            self.evaluate()
        }
        var address = Self.devicesAddress
        let status = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &address, queue, block
        )
        if status == OSStatus(kCMIOHardwareNoError) {
            deviceListListener = block
        }
    }

    private func resubscribeDevices() {
        let current = Set(Self.videoInputDevices())
        for (device, block) in deviceListeners where !current.contains(device) {
            var address = Self.runningAddress
            _ = CMIOObjectRemovePropertyListenerBlock(device, &address, queue, block)
            deviceListeners[device] = nil
        }
        for device in current where deviceListeners[device] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.isRunning else { return }
                self.evaluate()
            }
            var address = Self.runningAddress
            let status = CMIOObjectAddPropertyListenerBlock(device, &address, queue, block)
            if status == OSStatus(kCMIOHardwareNoError) {
                deviceListeners[device] = block
            }
        }
    }

    private func removeAllListeners() {
        for (device, block) in deviceListeners {
            var address = Self.runningAddress
            _ = CMIOObjectRemovePropertyListenerBlock(device, &address, queue, block)
        }
        deviceListeners.removeAll()
        if let block = deviceListListener {
            var address = Self.devicesAddress
            _ = CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject), &address, queue, block
            )
            deviceListListener = nil
        }
    }

    // MARK: - Reading

    private func evaluate() {
        let viaCoreMediaIO = deviceListeners.keys.contains { Self.isRunningSomewhere($0) }
        let active = viaCoreMediaIO || Self.anyCaptureDeviceInUseElsewhere()
        guard active != lastReported else { return }
        lastReported = active
        handler?(active)
    }

    /// CoreMediaIO devices that expose at least one input stream.
    static func videoInputDevices() -> [CMIOObjectID] {
        var address = devicesAddress
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == OSStatus(kCMIOHardwareNoError),
              size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buffer in
            CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, buffer.baseAddress!)
        }
        guard status == OSStatus(kCMIOHardwareNoError) else { return [] }
        let filled = min(count, Int(used) / MemoryLayout<CMIOObjectID>.size)
        return devices.prefix(filled).filter(hasInputStreams)
    }

    private static func hasInputStreams(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return status == OSStatus(kCMIOHardwareNoError) && size > 0
    }

    /// Read with Atoll's wildcard address first; a driver that rejects wildcards is asked again
    /// on the global scope.
    private static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        let fallback = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for candidate in [runningAddress, fallback] {
            var address = candidate
            var running: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running
            )
            if status == OSStatus(kCMIOHardwareNoError) { return running != 0 }
        }
        return false
    }

    /// AVFoundation's view of the same thing; catches devices CoreMediaIO reports late.
    private static func anyCaptureDeviceInUseElsewhere() -> Bool {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.contains { $0.isInUseByAnotherApplication }
    }
}
