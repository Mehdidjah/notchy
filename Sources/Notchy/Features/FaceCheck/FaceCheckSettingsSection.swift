import SwiftUI

enum FaceSettingsAnchor: Hashable {
    case password
}

private struct FacePasswordSettingsActionKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openFacePasswordSettings: @MainActor () -> Void {
        get { self[FacePasswordSettingsActionKey.self] }
        set { self[FacePasswordSettingsActionKey.self] = newValue }
    }
}

/// Sections within the existing Face Check settings pane. Cameras open only on request.
struct FaceCheckSettingsSection: View {
    let controller: FaceCheckController
    @ObservedObject var unlock: MacUnlockController
    let preferences: FaceCheckPreferences
    let userSettings: UserSettings
    @StateObject private var devices = FaceCheckDeviceCatalog()
    @Environment(\.openFacePasswordSettings) private var openPassword
    @Environment(\.scenePhase) private var scenePhase

    init(userSettings: UserSettings, controller: FaceCheckController = .shared,
         unlock: MacUnlockController = .shared, preferences: FaceCheckPreferences = .shared) {
        self.userSettings = userSettings
        self.controller = controller
        self.unlock = unlock
        self.preferences = preferences
    }

    var body: some View {
        Group {
            Section {
                Label(unlock.isAuthorized ? "Session unlocked" : "Session locked",
                      systemImage: unlock.isAuthorized ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .onAppear { controller.loadIdentities(); unlock.refreshReadiness() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { unlock.refreshReadiness(); devices.refresh() }
            }
            FaceGeneralSettingsSection(preferences: preferences, unlock: unlock,
                                       appSettings: userSettings, devices: devices, openPassword: openPassword)
            FaceIdentitiesSettingsSection(controller: controller, unlock: unlock)
            MacUnlockSettingsSection(controller: unlock, faces: controller, preferences: preferences)
            FaceCameraSettingsSection(controller: controller, preferences: preferences, devices: devices)
            FaceRecognitionSettingsSection(preferences: preferences)
        }
    }
}
