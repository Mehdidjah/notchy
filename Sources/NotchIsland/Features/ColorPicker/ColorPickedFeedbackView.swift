import SwiftUI

/// The "Color Picked!" flag: a 60-pt rounded swatch over the hex, springing in from 80 % scale.
/// Driven by `ColorPickerService.isShowingPickedFeedback` and `lastPickedColor`; tap to copy
/// the hex again.
struct ColorPickedFeedbackView: View {
    let color: PickedColor
    let isShowing: Bool
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.color)
                .frame(width: 60, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 8)

            VStack(spacing: 4) {
                Text("Color Picked!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(color.hexString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(ColorPickerHUDBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 12)
        .environment(\.colorScheme, .dark)
        .scaleEffect(isShowing ? 1 : 0.8)
        .opacity(isShowing ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isShowing)
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Color picked \(color.hexString)")
    }
}
