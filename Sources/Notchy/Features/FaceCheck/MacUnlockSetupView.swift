import SwiftUI

struct MacUnlockSetupView: View {
    var controller: MacUnlockController = .shared
    var faces: FaceCheckController = .shared
    var preferences: FaceCheckPreferences = .shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac Face Unlock").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }.padding(20)
            Form { MacUnlockSettingsSection(controller: controller, faces: faces, preferences: preferences) }
                .formStyle(.grouped)
        }
        .frame(width: 540, height: 560)
    }
}
