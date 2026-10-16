import Foundation

/// Entry point for the battery feature: the power-source monitor, the temporary charging /
/// low / full alerts in the closed notch, the header battery (`BatteryHeaderButton`) and the
/// Battery settings pane.
@MainActor
enum BatteryFeature {
    /// Called when the header battery's popover opens or closes, so the host can keep the
    /// island open while it shows (`isBatteryPopoverActive`).
    static var onPopoverPresentationChanged: ((Bool) -> Void)?

    private static var activity: BatteryHUDActivity?

    static func start() {
        BatteryMonitor.shared.start()
        BatteryHUDController.shared.start()
        let activity = activity ?? BatteryHUDActivity()
        Self.activity = activity
        IslandActivityCenter.shared.register(activity)
        SettingsSectionRegistry.shared.register(.battery, id: "battery") { BatterySettingsSection() }
    }

    static func stop() {
        if let activity {
            IslandActivityCenter.shared.unregister(id: activity.activityID)
        }
        BatteryHUDController.shared.stop()
        BatteryMonitor.shared.stop()
    }
}
