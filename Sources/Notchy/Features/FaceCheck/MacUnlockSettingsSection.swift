import SwiftUI

struct MacUnlockSettingsSection: View {
    @ObservedObject var controller: MacUnlockController = .shared
    @ObservedObject var faces: FaceCheckController = .shared
    @ObservedObject var preferences: FaceCheckPreferences = .shared
    @State private var password = ""
    @State private var selectedIdentity: UUID?
    @State private var editing = false
    @State private var confirmRemoval = false
    @State private var setupTask: Task<Void, Never>?

    private var identity: FaceIdentity? {
        faces.identities.first { $0.id == (selectedIdentity ?? controller.boundIdentityID) && $0.isEnabled && $0.supportsPassiveUnlock }
            ?? faces.identities.first { $0.isEnabled && $0.supportsPassiveUnlock }
    }

    private var lifetimeIndex: Binding<Double> {
        Binding(get: { Double(FaceSessionLifetime.allCases.firstIndex(of: preferences.options.sessionLifetime) ?? 2) },
                set: { preferences.options.sessionLifetime = FaceSessionLifetime.allCases[Int(min(3, max(0, $0.rounded())))] })
    }

    var body: some View {
        Section("Password") {
            Label(controller.hasPassword ? "Password encrypted" : "No password saved",
                  systemImage: controller.hasPassword ? "lock.fill" : "key")
                .fontWeight(.medium)
            if let bound = faces.identities.first(where: { $0.id == controller.boundIdentityID }) {
                LabeledContent("Linked face", value: bound.name)
            }
            VStack(alignment: .leading) {
                HStack { Text("Auto lock session"); Spacer(); Text(preferences.options.sessionLifetime.title).foregroundStyle(.secondary) }
                Slider(value: lifetimeIndex, in: 0...3, step: 1).labelsHidden()
                    .accessibilityLabel("Auto lock password authorization session")
                Text("Authorize again after this many days without a face unlock, or after restarting Notchy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if controller.hasPassword {
                HStack {
                    Text("Change password")
                    Spacer()
                    Button("Change…") { editing = true }.disabled(controller.isBusy)
                }
                HStack {
                    Text("Remove password")
                    Spacer()
                    Button("Remove…", role: .destructive) { confirmRemoval = true }.disabled(controller.isBusy)
                }
                HStack {
                    Text(controller.isAuthorized ? "Session unlocked" : "Session locked")
                    Spacer()
                    if controller.isAuthorized {
                        Button("Lock session") { controller.lockAuthorization() }
                    } else {
                        Button("Authorize Face Unlock") { authorize() }
                            .disabled(controller.isBusy || controller.setupUnavailableReason != nil)
                    }
                }
            } else if controller.canRemovePassword {
                Button("Remove unavailable password…", role: .destructive) { confirmRemoval = true }
            }
        }
        .id(FaceSettingsAnchor.password)

        if editing || !controller.hasPassword {
            Section(controller.hasPassword ? "Change your Mac password" : "Link your Mac password") {
                if let reason = controller.setupUnavailableReason {
                    Text(reason).foregroundStyle(.secondary)
                } else if identity == nil {
                    Text("Add or recapture an enabled face above first.").foregroundStyle(.secondary)
                } else {
                    Picker("Face allowed to unlock this Mac", selection: Binding(get: { identity?.id }, set: { selectedIdentity = $0 })) {
                        ForEach(faces.identities.filter { $0.isEnabled && $0.supportsPassiveUnlock }) { face in
                            Text(face.name).tag(Optional(face.id))
                        }
                    }
                    SecureField("Mac login password", text: $password)
                        .textContentType(.password).privacySensitive().onSubmit { save() }
                    HStack {
                        if controller.hasPassword { Button("Cancel") { password = ""; editing = false } }
                        Spacer()
                        if controller.isBusy { ProgressView().controlSize(.small) }
                        Button("Save password & enable") { save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(password.isEmpty || identity == nil || identity?.supportsPassiveUnlock != true || controller.isBusy)
                    }
                }
            }
            .disabled(controller.isBusy)
        }
        Section {
            if controller.isExperimental {
                Text("Experimental: photo/video protection has not yet passed the live-camera validation trials.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !controller.accessibilityGranted { FaceAccessibilityButton() }
            if case .failed(let message) = controller.state { Text(message).foregroundStyle(.orange) }
            Text("Your login password is encrypted on this Mac and protected by system authentication. Only its linked face can unlock this account. Adding another face does not give it access to this password.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The first login after restarting or logging out still requires your Mac password.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { controller.refreshReadiness() }
        .onDisappear {
            password = ""
            if setupTask != nil {
                setupTask?.cancel()
                setupTask = nil
                controller.cancelSetup()
            }
        }
        .confirmationDialog("Remove the saved Mac password?", isPresented: $confirmRemoval) {
            Button("Remove password", role: .destructive) { controller.removePassword() }
        } message: { Text("Face Unlock stops. Your saved faces remain available for in-app checks.") }
    }

    private func save() {
        guard let identity, identity.supportsPassiveUnlock, controller.setupUnavailableReason == nil,
              !password.isEmpty, !controller.isBusy, setupTask == nil else { return }
        let entered = password
        password = ""
        setupTask = Task {
            guard !Task.isCancelled else { return }
            await controller.save(password: entered, identity: identity)
            guard !Task.isCancelled else { return }
            setupTask = nil
            if controller.isAuthorized, controller.boundIdentityID == identity.id { editing = false }
        }
    }

    private func authorize() {
        guard setupTask == nil, !controller.isBusy else { return }
        setupTask = Task {
            guard !Task.isCancelled else { return }
            await controller.authorizeSession()
            guard !Task.isCancelled else { return }
            setupTask = nil
        }
    }
}
