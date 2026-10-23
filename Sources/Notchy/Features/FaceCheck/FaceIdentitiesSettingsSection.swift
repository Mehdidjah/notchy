import SwiftUI

struct FaceIdentitiesSettingsSection: View {
    @ObservedObject var controller: FaceCheckController
    @ObservedObject var unlock: MacUnlockController
    @State private var adding = false
    @State private var name = "Me"
    @State private var deleting: FaceIdentity?
    @State private var deleteAll = false

    private var busy: Bool { controller.activity != .watching || controller.isPreparingEnrollment }

    var body: some View {
        Section {
            Label(controller.identities.isEmpty ? "Face data stays on this Mac" : "Faces encrypted", systemImage: "lock.fill")
                .fontWeight(.medium)
            Text("Add separate identities for different people or appearances. Captures are stored as encrypted face descriptors; camera pictures are never saved.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section {
            HStack {
                Text("Identities").fontWeight(.medium)
                Spacer()
                if !controller.identities.isEmpty {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .help("Add a face").accessibilityLabel("Add a face").disabled(busy)
                }
            }
            if controller.identities.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Follow the circular camera guide to capture all nine positions and save your face.")
                        .foregroundStyle(.secondary)
                    Button("Scan face") { adding = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
            } else {
                Text("Use Recapture to scan a saved face again with the circular camera guide.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(controller.identities) { identity in
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: {
                        controller.identities.first(where: { $0.id == identity.id })?.isEnabled == true
                    }, set: { controller.setIdentityEnabled($0, identity: identity) })) {
                        HStack {
                            Text(identity.name).fontWeight(.medium)
                            if unlock.boundIdentityID == identity.id {
                                Label("Linked to password", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    HStack(alignment: .bottom) {
                        FaceCaptureQualityView(identity: identity)
                        Spacer()
                        Button("Recapture") { controller.startMacUnlockEnrolment(name: identity.name, replacing: identity) }
                            .help("Replace these captures after a complete scan. A linked password must be bound again.")
                        Button(role: .destructive) { deleting = identity } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete \(identity.name)")
                    }
                    if !identity.supportsPassiveUnlock {
                        Text("Recapture this face to use Mac Face Unlock.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6).disabled(busy)
            }
        }
        Section {
            if let problem = controller.storeProblem { Text(problem).foregroundStyle(.red) }
            if controller.isPreparingEnrollment { ProgressView("Authorizing capture…") }
            if controller.activity == .enrolling {
                Text("Follow the circular guide at the top of your screen.")
                Button("Cancel scan") { controller.cancelEnrolment() }
            }
            Button("Delete all face data…", role: .destructive) { deleteAll = true }
                .disabled(busy || (controller.identities.isEmpty && controller.storeProblem == nil))
        }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a face").font(.title2.weight(.semibold))
                Text("Name this identity, then follow all nine positions in the circular guide.").foregroundStyle(.secondary)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Start scan") {
                        adding = false
                        controller.startMacUnlockEnrolment(name: name)
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 380)
        }
        .confirmationDialog("Delete this face?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { face in
            Button("Delete \(face.name)", role: .destructive) { controller.deleteIdentity(face); deleting = nil }
        } message: { _ in Text("A password linked to this face will stop unlocking your Mac.") }
        .confirmationDialog("Delete all face data?", isPresented: $deleteAll) {
            Button("Delete all", role: .destructive) { controller.deleteAllFaceData() }
        }
    }
}

struct FaceCaptureQualityView: View {
    let identity: FaceIdentity
    private var samples: [FaceSample] {
        let current = identity.samples(forModel: FaceRecognitionProfile.auraFace.identifier)
        return current.isEmpty ? identity.samples : current
    }
    private var qualities: [Double] { samples.map { FaceCheckOptions.clamp($0.quality, to: 0...1, fallback: 0) } }
    private var percent: Int { Int((qualities.reduce(0, +) / Double(max(1, qualities.count)) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Capture quality · \(percent)%").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(Array(qualities.prefix(36).enumerated()), id: \.offset) { _, quality in
                    Capsule().fill(quality >= 0.7 ? Color.green : quality >= 0.45 ? .orange : .red)
                        .frame(width: 3, height: 20)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capture quality \(percent) percent, \(identity.capturedViewCount) views")
    }
}
