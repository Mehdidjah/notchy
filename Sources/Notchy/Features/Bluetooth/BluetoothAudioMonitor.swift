import AppKit
import Combine
import IOBluetooth

/// Tracks connected Bluetooth audio devices with IOBluetooth's public connect and per-device
/// disconnect notifications, and announces each new connection once.
///
/// IOBluetooth delivers its notifications on the run loop of the thread that registered, so
/// everything here stays on the main actor.
@MainActor
final class BluetoothAudioMonitor: ObservableObject {
    static let shared = BluetoothAudioMonitor()

    @Published private(set) var connectedDevices: [BluetoothAudioDevice] = []
    /// The most recently connected device, kept after it disconnects (the label source).
    @Published private(set) var lastConnectedDevice: BluetoothAudioDevice?
    /// Each newly connected audio device, once. Devices already connected at start are not
    /// announced.
    let connections = PassthroughSubject<BluetoothAudioDevice, Never>()
    let disconnections = PassthroughSubject<BluetoothAudioDevice, Never>()

    /// True while any Bluetooth audio device is connected; the volume HUD shows headphones then.
    var isBluetoothAudioConnected: Bool { !connectedDevices.isEmpty }

    private(set) var isRunning = false

    private let bridge = BluetoothNotificationBridge()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var wakeObserver: NSObjectProtocol?

    init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        bridge.onConnect = { [weak self] device in self?.deviceDidConnect(device, announce: true) }
        bridge.onDisconnect = { [weak self] device in self?.deviceDidDisconnect(device) }
        // Learn what is already connected first, so the registration's initial callbacks for
        // those devices are recognised and stay quiet.
        resync(announce: false)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: bridge,
            selector: #selector(BluetoothNotificationBridge.deviceConnected(_:device:))
        )
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resync(announce: false) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        bridge.onConnect = nil
        bridge.onDisconnect = nil
        connectedDevices.removeAll()
    }

    /// Re-reads the paired devices: adds connected audio devices that were missed and drops
    /// ones that went away (for example across sleep).
    func resync(announce: Bool) {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let poweredOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        let connected = poweredOn ? paired.filter { $0.isConnected() && Self.isAudioDevice($0) } : []
        let connectedAddresses = Set(connected.compactMap(\.addressString))
        for device in connectedDevices where !connectedAddresses.contains(device.address) {
            removeDevice(address: device.address)
        }
        for device in connected {
            deviceDidConnect(device, announce: announce)
        }
    }

    private func deviceDidConnect(_ device: IOBluetoothDevice, announce: Bool) {
        guard Self.isAudioDevice(device), let record = Self.makeDevice(from: device) else { return }
        guard !connectedDevices.contains(where: { $0.address == record.address }) else { return }
        connectedDevices.append(record)
        lastConnectedDevice = record
        disconnectNotifications[record.address]?.unregister()
        disconnectNotifications[record.address] = device.register(
            forDisconnectNotification: bridge,
            selector: #selector(BluetoothNotificationBridge.deviceDisconnected(_:device:))
        )
        if announce {
            connections.send(record)
        }
    }

    private func deviceDidDisconnect(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        removeDevice(address: address)
    }

    private func removeDevice(address: String) {
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        guard let index = connectedDevices.firstIndex(where: { $0.address == address }) else { return }
        let removed = connectedDevices.remove(at: index)
        disconnections.send(removed)
    }

    // MARK: Classification

    /// Audio devices advertise an audio sink, headset or hands-free service, or carry the
    /// Audio/Video major device class.
    static func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        let audioServices: [BluetoothSDPUUID16] = [0x110B, 0x1108, 0x111E]
        for service in audioServices where device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: service)) != nil {
            return true
        }
        return isAudioVideoClass(device.classOfDevice)
    }

    static func isAudioVideoClass(_ classOfDevice: UInt32) -> Bool {
        (classOfDevice >> 8) & 0x1F == 0x04
    }

    private static func makeDevice(from device: IOBluetoothDevice) -> BluetoothAudioDevice? {
        guard let address = device.addressString else { return nil }
        let name = device.name ?? device.nameOrAddress ?? "Bluetooth Device"
        return BluetoothAudioDevice(
            address: address,
            name: name,
            kind: BluetoothAudioDeviceKind.detect(
                name: name,
                classOfDevice: device.classOfDevice,
                appleProductID: appleProductID(of: device)
            )
        )
    }

    /// The product ID from the device's Device ID (PnP Information) record, when its vendor
    /// is Apple (0x004C from the Bluetooth SIG, or 0x05AC from USB-IF).
    private static func appleProductID(of device: IOBluetoothDevice) -> UInt16? {
        guard let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1200)),
              let vendor = record.getAttributeDataElement(0x0201)?.getNumberValue()?.uint16Value,
              vendor == 0x004C || vendor == 0x05AC,
              let product = record.getAttributeDataElement(0x0202)?.getNumberValue()?.uint16Value
        else { return nil }
        return product
    }
}

/// Receives IOBluetooth's Objective-C notifications and forwards them as closures.
@MainActor
private final class BluetoothNotificationBridge: NSObject {
    var onConnect: ((IOBluetoothDevice) -> Void)?
    var onDisconnect: ((IOBluetoothDevice) -> Void)?

    @objc func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect?(device)
    }

    @objc func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onDisconnect?(device)
    }
}
