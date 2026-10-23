import SwiftUI

/// Sections within the existing Face Check settings pane. Cameras open only on request.
struct FaceCheckSettingsSection: View {
    let controller: FaceCheckController
    @ObservedObject var unlock: MacUnlockController
    let preferences: FaceCheckPreferences
    let userSettings: UserSettings
    @StateObject private var devices = FaceCheckDeviceCatalog()
    @State private var passwordSetup = false
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
            .sheet(isPresented: $passwordSetup) {
                MacUnlockSetupView(controller: unlock, faces: controller, preferences: preferences)
            }
            FaceGeneralSettingsSection(preferences: preferences, unlock: unlock,
                                       appSettings: userSettings, devices: devices) { passwordSetup = true }
            FaceIdentitiesSettingsSection(controller: controller, unlock: unlock)
            MacUnlockSettingsSection(controller: unlock, faces: controller, preferences: preferences)
            FaceCameraSettingsSection(controller: controller, preferences: preferences, devices: devices)
            FaceRecognitionSettingsSection(preferences: preferences)
        }
    }
}
