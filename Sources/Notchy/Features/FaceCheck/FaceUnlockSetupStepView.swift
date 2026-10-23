import ApplicationServices
import SwiftUI

/// Password entry stays in the same notch surface as enrollment.
struct FaceUnlockSetupStepView: View {
    @ObservedObject var session: FaceUnlockSetupSession
    var hasHardwareNotch: Bool
    var isExpanded: Bool
    var compactWidth: CGFloat
    var compactHeight: CGFloat
    var cancel: () -> Void
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    var body: some View {
        FaceUnlockSetupCard(stage: session.stage, error: session.error, isSaving: session.isSaving,
                            unavailableReason: session.unavailableReason,
                            isExperimental: session.isExperimental,
                            hasHardwareNotch: hasHardwareNotch, isExpanded: isExpanded,
                            compactWidth: compactWidth, compactHeight: compactHeight,
                            drawsBackground: false,
                            cancel: cancel, confirm: submit, allowAccessibility: allowAccessibility) {
            SecureField("Mac login password", text: $password)
                .textFieldStyle(.plain)
                .textContentType(.password)
                .privacySensitive()
                .focused($passwordFocused)
                .disabled(session.isSaving)
                .onSubmit(submit)
        }
        .onDisappear { password = "" }
        .onChange(of: session.stage) { _, next in
            if next != .password { password = "" }
        }
        .task(id: session.stage) {
            if session.stage == .password, session.unavailableReason == nil {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                passwordFocused = true
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            if session.stage == .permission { session.refreshPermission() }
        }
        .onExitCommand(perform: cancel)
    }

    private func submit() {
        guard !password.isEmpty, !session.isSaving else { return }
        let entered = password
        password = ""
        session.submit(password: entered)
    }

    private func allowAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        session.refreshPermission()
    }
}

/// Shared by the live secure field and deterministic, credential-free previews.
struct FaceUnlockSetupCard<Field: View>: View {
    var stage: FaceUnlockSetupSession.Stage
    var error: String?
    var isSaving = false
    var unavailableReason: String? = nil
    var isExperimental = false
    var hasHardwareNotch = true
    var isExpanded = true
    var compactWidth: CGFloat = 201
    var compactHeight: CGFloat = 32
    var animates = true
    var drawsBackground = true
    var cancel: () -> Void = {}
    var confirm: () -> Void = {}
    var allowAccessibility: () -> Void = {}
    @ViewBuilder var field: () -> Field
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var complete: Bool { stage == .complete }
    private var width: CGFloat { 380 + (hasHardwareNotch ? 32 : 0) }
    private var height: CGFloat { complete ? 96 : 260 }

    var body: some View {
        ZStack(alignment: .top) {
            if drawsBackground {
                silhouette.fill(.black)
                    .frame(width: isExpanded ? width : compactWidth,
                           height: isExpanded ? height : compactHeight)
            }
            content
                .frame(width: 380, height: height, alignment: .top)
                .opacity(isExpanded ? 1 : 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .animation(animates && !reduceMotion ? .spring(response: 0.45, dampingFraction: isExpanded ? 0.7 : 1) : nil,
                   value: isExpanded)
        .animation(animates && !reduceMotion ? .spring(response: 0.45, dampingFraction: 0.8) : nil, value: stage)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if complete {
            HStack {
                Text("You're all set").font(.system(size: 24, weight: .bold))
                Spacer()
                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.top, 42)
        } else if stage == .permission {
            VStack(alignment: .leading, spacing: 14) {
                Text("Allow password entry").font(.system(size: 24, weight: .bold))
                Text("Your face and password are saved. Allow Notchy in Accessibility so it can enter your password on the lock screen.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                actions(secondary: "Not now", primary: "Open Settings", action: allowAccessibility)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 26)
        } else if let unavailableReason {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Face saved").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(FaceEnrollmentPresentation.accent)
                        .accessibilityHidden(true)
                }
                Text("Your face is saved on this Mac.")
                    .font(.system(size: 13))
                Text(unavailableReason)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Text("Done").frame(maxWidth: .infinity).frame(height: 38)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .background(FaceEnrollmentPresentation.accent, in: Capsule())
                .keyboardShortcut(.defaultAction)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 26)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Enter your password").font(.system(size: 24, weight: .bold))
                Text(isExperimental
                     ? "Experimental: photo/video protection is not yet validated. Notchy will enter your password after a matching live-face check."
                     : "Your face is saved. Notchy will enter your Mac password after recognizing you on the lock screen.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                field()
                    .font(.system(size: 13))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(.white.opacity(0.12), in: Capsule())
                    .padding(.top, 14)
                Text(error ?? " ")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .lineLimit(2).frame(height: 28, alignment: .center)
                actions(secondary: "Not now", primary: isSaving ? "Saving…" : "Save & enable", action: confirm)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.top, 40)
        }
    }

    private func actions(secondary: String, primary: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: cancel) { Text(secondary).frame(maxWidth: .infinity).frame(height: 38) }
                .background(.white.opacity(0.12), in: Capsule())
            Button(action: action) { Text(primary).frame(maxWidth: .infinity).frame(height: 38) }
                .background(FaceEnrollmentPresentation.accent, in: Capsule())
                .disabled(isSaving || unavailableReason != nil)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
    }

    private var silhouette: AnyShape {
        hasHardwareNotch
            ? AnyShape(FaceEnrollmentSilhouette())
            : AnyShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
    }
}

/// One silhouette morphs between capture, password entry and completion while the content
/// crossfades. The surrounding native window stays anchored to the top of the display.
struct FaceUnlockSetupSurface<Scan: View, Steps: View>: View {
    var stage: FaceUnlockSetupSession.Stage
    var hasHardwareNotch = true
    var isExpanded = true
    var compactWidth: CGFloat = 201
    var compactHeight: CGFloat = 32
    var animates = true
    @ViewBuilder var scan: () -> Scan
    @ViewBuilder var steps: () -> Steps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Bool { animates && !reduceMotion }
    private var width: CGFloat { (stage.showsCredentialStep ? 380 : 320) + (hasHardwareNotch ? 32 : 0) }
    private var height: CGFloat {
        if stage == .complete { return 96 }
        return stage.showsCredentialStep ? 260 : (hasHardwareNotch ? 344 : 350)
    }

    var body: some View {
        ZStack(alignment: .top) {
            let shape = hasHardwareNotch ? AnyShape(FaceEnrollmentSilhouette())
                : AnyShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
            shape.fill(.black)
                .frame(width: isExpanded ? width : compactWidth, height: isExpanded ? height : compactHeight)
                .animation(motion ? .spring(response: 0.45, dampingFraction: 0.8) : nil, value: stage)
                .animation(motion ? .spring(response: 0.45, dampingFraction: isExpanded ? 0.7 : 1) : nil, value: isExpanded)
            Group {
                if stage.showsCredentialStep { steps() }
                else { scan() }
            }
            .transition(.opacity)
            .animation(motion ? .easeInOut(duration: 0.2) : nil, value: stage.showsCredentialStep)
        }
        .frame(width: hasHardwareNotch ? 412 : 380, height: hasHardwareNotch ? 344 : 350, alignment: .top)
    }
}
