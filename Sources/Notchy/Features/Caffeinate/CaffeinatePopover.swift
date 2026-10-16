import AppKit
import SwiftUI

/// The 240-pt Keep Awake popover under the cup button: a status header, one row per duration
/// (a check marks the running one; choosing another restarts with it) and, while a session runs,
/// a Turn Off button. Every choice closes the popover.
struct CaffeinatePopover: View {
    @ObservedObject var controller: CaffeinateController
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .padding(.horizontal, -8)

            VStack(spacing: 2) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    durationRow(duration)
                }
            }

            if controller.isActive {
                Divider()
                    .padding(.horizontal, -8)

                Button {
                    withAnimation(.smooth) { controller.deactivate() }
                    dismiss()
                } label: {
                    Text("Turn Off")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(
            CaffeinateHUDBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(controller.isActive ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text("Keep Awake")
                    .font(.system(size: 13, weight: .semibold))
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // The countdown keeps a fixed width so the popover does not reflow each second.
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private func durationRow(_ duration: CaffeinateDuration) -> some View {
        let isRunning = controller.isActive && controller.activeDuration == duration
        return Button {
            withAnimation(.smooth) { controller.activate(for: duration) }
            dismiss()
        } label: {
            HStack {
                Text(duration.displayName)
                Spacer()
                if isRunning {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityAddTraits(isRunning ? .isSelected : [])
    }
}

/// The HUD material behind the popover. It follows the system appearance rather
/// than forcing dark, so text and material always agree with the popover chrome.
private struct CaffeinateHUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
