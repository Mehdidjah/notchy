import Foundation

/// Entry point for the Bluetooth audio feature: the IOBluetooth connection monitor and the
/// "device connected" HUD (inline in the closed notch, or a sneak peek), and its rows in the
/// Devices settings pane.
@MainActor
enum BluetoothFeature {
    /// Called with 1.5 s each time the connection HUD shows, so the host can keep the volume
    /// HUD quiet while the output switches to the headphones (Atoll's HUD suppression).
    static var onSuppressVolumeHUD: ((TimeInterval) -> Void)?

    private static var activity: BluetoothHUDActivity?

    static func start() {
        BluetoothAudioMonitor.shared.start()
        BluetoothHUDController.shared.start()
        let activity = activity ?? BluetoothHUDActivity()
        Self.activity = activity
        IslandActivityCenter.shared.register(activity)
        SettingsSectionRegistry.shared.register(.devices, id: "bluetooth") { BluetoothSettingsSection() }
    }

    static func stop() {
        if let activity {
            IslandActivityCenter.shared.unregister(id: activity.activityID)
        }
        BluetoothHUDController.shared.stop()
        BluetoothAudioMonitor.shared.stop()
    }
}
