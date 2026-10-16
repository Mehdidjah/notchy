import Combine
import SwiftUI

/// One showing of the Bluetooth connection HUD.
struct BluetoothHUDPresentation: Equatable, Identifiable, Sendable {
    let id: UUID
    let device: BluetoothAudioDevice
    /// 0...100, or nil when the level is unknown (the right wing then shrinks).
    let batteryLevel: Int?

    /// Atoll draws the battery only for a known, non-zero level.
    var showsBattery: Bool { (batteryLevel ?? 0) > 0 }
}

/// Shows the "device connected" HUD for 2.5 s: inline beside the notch (Atoll's default) or
/// as a sneak-peek row under it.
@MainActor
final class BluetoothHUDController: ObservableObject {
    static let shared = BluetoothHUDController()

    /// Atoll's Bluetooth sneak duration.
    nonisolated static let displayDuration: Duration = .milliseconds(2_500)
    /// Atoll waits up to 1.8 s for a battery reading before showing the HUD without one.
    nonisolated static let batteryWait: Duration = .milliseconds(1_800)
    /// Atoll keeps volume HUDs quiet for 1.5 s after a Bluetooth HUD, since connecting
    /// headphones changes the output volume.
    nonisolated static let volumeHUDSuppression: TimeInterval = 1.5

    @Published private(set) var presentation: BluetoothHUDPresentation?
    /// Volume HUDs should stay hidden until this moment.
    @Published private(set) var volumeHUDSuppressedUntil: Date?

    let monitor: BluetoothAudioMonitor
    let settings: BluetoothSettings
    private let batteryReader: @Sendable (Duration) async -> BluetoothBatteryReport?
    private let activityCenter: IslandActivityCenter

    private var subscriptions: Set<AnyCancellable> = []
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    private var hideTask: Task<Void, Never>?

    init(
        monitor: BluetoothAudioMonitor = .shared,
        settings: BluetoothSettings = .shared,
        activityCenter: IslandActivityCenter = .shared,
        batteryReader: @escaping @Sendable (Duration) async -> BluetoothBatteryReport? = { timeout in
            await BluetoothBatteryReader.read(timeout: timeout)
        }
    ) {
        self.monitor = monitor
        self.settings = settings
        self.activityCenter = activityCenter
        self.batteryReader = batteryReader
    }

    /// True while a volume HUD should not appear.
    var suppressesVolumeHUD: Bool {
        guard let volumeHUDSuppressedUntil else { return false }
        return volumeHUDSuppressedUntil > Date()
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        monitor.connections
            .sink { [weak self] device in self?.deviceDidConnect(device) }
            .store(in: &subscriptions)
        monitor.disconnections
            .sink { [weak self] device in self?.deviceDidDisconnect(device) }
            .store(in: &subscriptions)
    }

    func stop() {
        subscriptions.removeAll()
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        hideTask?.cancel()
        hideTask = nil
        presentation = nil
    }

    func deviceDidConnect(_ device: BluetoothAudioDevice) {
        guard settings.showDeviceConnections else { return }
        pendingTasks[device.address]?.cancel()
        let readsBattery = settings.readBatteryLevels
        let reader = batteryReader
        pendingTasks[device.address] = Task { [weak self] in
            let report = readsBattery ? await reader(Self.batteryWait) : nil
            guard !Task.isCancelled, let self else { return }
            self.pendingTasks[device.address] = nil
            self.present(device, batteryLevel: report?.level(address: device.address, name: device.name))
        }
    }

    func deviceDidDisconnect(_ device: BluetoothAudioDevice) {
        pendingTasks.removeValue(forKey: device.address)?.cancel()
    }

    /// Shows the HUD now, inline or as a sneak peek per the settings.
    func present(_ device: BluetoothAudioDevice, batteryLevel: Int?) {
        guard settings.showDeviceConnections else { return }
        let level = batteryLevel.map { min(max($0, 0), 100) }
        volumeHUDSuppressedUntil = Date().addingTimeInterval(Self.volumeHUDSuppression)
        BluetoothFeature.onSuppressVolumeHUD?(Self.volumeHUDSuppression)
        if settings.useInlineHUD {
            withAnimation(.smooth(duration: 0.3)) {
                presentation = BluetoothHUDPresentation(id: UUID(), device: device, batteryLevel: level)
            }
            scheduleHide()
        } else {
            activityCenter.requestSneakPeek(sneakPeek(for: device, batteryLevel: level))
        }
    }

    /// The standard (non-inline) style, as Atoll draws it under the notch: the device symbol
    /// and a battery-coloured level bar. Atoll passes 0 when the level is unknown, so the bar
    /// is then empty; it never shows a text line for a connection.
    func sneakPeek(for device: BluetoothAudioDevice, batteryLevel: Int?) -> SneakPeek {
        let fraction = Double(min(max(batteryLevel ?? 0, 0), 100)) / 100
        return SneakPeek(
            kind: .bluetooth,
            systemImage: device.kind.systemImage,
            title: "Connected",
            subtitle: device.name,
            level: fraction,
            tint: settings.useColorCodedBatteryDisplay
                ? BluetoothBatteryPalette.color(forLevel: fraction, smooth: settings.useSmoothColorGradient)
                : .white,
            duration: Self.displayDuration
        )
    }

    /// Shows the HUD for the last connected device, or a sample pair of AirPods Pro.
    func triggerTestHUD() {
        let device = monitor.lastConnectedDevice
            ?? BluetoothAudioDevice(address: "00-00-00-00-00-00", name: "AirPods Pro", kind: .airpodsPro)
        present(device, batteryLevel: monitor.lastConnectedDevice == nil ? 80 : nil)
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        guard presentation != nil else { return }
        withAnimation(.smooth(duration: 0.3)) { presentation = nil }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            withAnimation(.smooth(duration: 0.3)) { self.presentation = nil }
        }
    }
}
