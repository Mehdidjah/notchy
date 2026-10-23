import ApplicationServices
import SwiftUI

struct MacUnlockSettingsSection: View {
    @ObservedObject var controller: MacUnlockController = .shared
    @ObservedObject var faces: FaceCheckController = .shared
    @State private var password = ""
    @State private var selectedIdentity: UUID?
    @State private var confirmRemoval = false

    private var identity: FaceIdentity? {
        faces.identities.first { $0.id == (selectedIdentity ?? controller.boundIdentityID) && $0.isEnabled }
            ?? faces.identities.first { $0.isEnabled }
    }

    private var readiness: String {
        if !controller.isEnabled || !controller.isAuthorized { return "Face Unlock is paused" }
        if !controller.accessibilityGranted { return "Allow Accessibility to finish setup" }
        if case .failed = controller.state { return "Face Unlock needs attention" }
        return "Face Unlock is ready"
    }

    var body: some View {
        Section("Unlock your Mac") {
            Text("Save your Mac login password once. When your Mac locks or wakes, Notchy checks your saved face and looks for signs of a photo or screen, then enters the password for you. You don't need to blink or turn your head.")
                .font(.callout).foregroundStyle(.secondary)

            if controller.isExperimental {
                Text("Experimental build: face recognition and photo/video rejection have not yet passed the live-camera validation trials.")
                    .font(.callout).foregroundStyle(.orange)
            }

            if let reason = controller.setupUnavailableReason {
                Text(reason).foregroundStyle(.secondary)
            } else if identity == nil {
                Text("Scan and enable a saved face first.").foregroundStyle(.secondary)
            } else if identity?.supportsPassiveUnlock != true {
                Text("Scan your face again in the Face tab before setting up Face Unlock.").foregroundStyle(.secondary)
            } else {
                if faces.identities.filter(\.isEnabled).count > 1 {
                    Picker("Face allowed to unlock this Mac", selection: Binding(
                        get: { identity?.id }, set: { selectedIdentity = $0 }
                    )) {
                        ForEach(faces.identities.filter(\.isEnabled)) { face in
                            Text(face.name).tag(Optional(face.id))
                        }
                    }
                }
                SecureField(controller.hasPassword ? "New Mac login password" : "Mac login password", text: $password)
                    .textContentType(.password)
                    .privacySensitive()
                    .disabled(controller.isBusy)
                    .onSubmit { save() }
                HStack {
                    Button(controller.hasPassword ? "Update password" : "Save password & enable") { save() }
                        .disabled(password.isEmpty || identity == nil || controller.isBusy)
                    if controller.isBusy { ProgressView().controlSize(.small) }
                }
            }

            if controller.hasPassword {
                HStack {
                    Label(readiness,
                          systemImage: controller.isEnabled && controller.isAuthorized ? "lock.open" : "lock")
                    Spacer()
                    if controller.isEnabled && controller.isAuthorized {
                        Button("Pause") { controller.disable() }
                    } else {
                        Button("Authorize Face Unlock") { Task { await controller.authorizeSession() } }
                            .disabled(controller.isBusy || controller.setupUnavailableReason != nil)
                    }
                }
            }
            if controller.canRemovePassword {
                Button("Remove saved password…", role: .destructive) { confirmRemoval = true }
                    .disabled(controller.isBusy)
            }

            if !controller.accessibilityGranted {
                HStack {
                    Text("Accessibility access is needed to enter the password.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow Accessibility") {
                        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if case .failed(let message) = controller.state {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            Text("Your password stays encrypted on this Mac, protected by system authentication. Authorize once each time Notchy starts, then keep it running for future unlocks. The first login after a restart or logout still needs your password.")
                .font(.caption).foregroundStyle(.secondary)
            Text("A webcam can be fooled by a convincing photo or video. Face Unlock is optional and does not provide the security of Touch ID. Lock-screen support can change after macOS updates.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { controller.refreshReadiness() }
        .onDisappear { password = "" }
        .confirmationDialog("Remove the saved Mac password?", isPresented: $confirmRemoval) {
            Button("Remove password", role: .destructive) { controller.removePassword() }
        } message: {
            Text("Face Unlock stops. Your enrolled face remains available for in-app checks.")
        }
    }

    private func save() {
        guard let identity, identity.supportsPassiveUnlock, controller.setupUnavailableReason == nil,
              !password.isEmpty, !controller.isBusy else { return }
        let enteredPassword = password
        password = ""
        Task { await controller.save(password: enteredPassword, identity: identity) }
    }
}

struct MacUnlockSetupView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac Face Unlock").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }.padding(20)
            Form { MacUnlockSettingsSection() }.formStyle(.grouped)
        }
        .frame(width: 540, height: 560)
    }
}
