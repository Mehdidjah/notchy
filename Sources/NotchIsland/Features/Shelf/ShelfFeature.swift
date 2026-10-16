import SwiftUI

/// One-call wiring for the host: registers the closed-notch count indicator and the
/// settings rows. Everything else in the shelf is reached through `NotchShelfTabView`,
/// `ShelfDropDetectorModifier` and `ShelfStore.shared`.
@MainActor
enum ShelfFeature {
    static let settingsSectionID = "shelf.settings"

    static func start(
        store: ShelfStore = .shared,
        settings: ShelfSettings = .shared,
        userSettings: UserSettings? = nil,
        activityCenter: IslandActivityCenter = .shared,
        settingsRegistry: SettingsSectionRegistry = .shared
    ) {
        activityCenter.register(ShelfLiveActivity(store: store, settings: userSettings))
        settingsRegistry.register(.shelf, id: settingsSectionID) {
            ShelfSettingsSection(settings: settings)
        }
    }
}
