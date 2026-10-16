import Foundation

/// Entry point for the system HUDs: volume, brightness and microphone HUDs (inline or
/// standard style), the media-key tap (volume interception, brightness-key reporting), and
/// the Caps Lock indicator.
@MainActor
enum SystemHUDFeature {
    static let inlineActivity = InlineHUDActivity(
        presenter: .shared,
        onDrag: { value in SystemHUDManager.shared.userDraggedVolume(to: value) }
    )
    static let capsLockActivity = CapsLockActivity()

    private(set) static var isRunning = false

    static func start() {
        guard !isRunning else { return }
        isRunning = true
        SystemHUDManager.shared.start()
        IslandActivityCenter.shared.register(inlineActivity)
        IslandActivityCenter.shared.register(capsLockActivity)
        // The HUD rows go in the Controls pane and the Caps Lock rows in Live
        // Activities.
        SettingsSectionRegistry.shared.register(.controls, id: "systemHUD") {
            SystemHUDSettingsSection(includesCapsLock: false)
        }
        SettingsSectionRegistry.shared.register(.liveActivities, id: "capsLock") {
            CapsLockSettingsSection()
        }
    }

    static func stop() {
        guard isRunning else { return }
        isRunning = false
        IslandActivityCenter.shared.unregister(id: inlineActivity.activityID)
        IslandActivityCenter.shared.unregister(id: capsLockActivity.activityID)
        SystemHUDManager.shared.stop()
    }
}
