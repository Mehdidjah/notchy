import SwiftUI

/// The island header's round buttons: a dark grey disc with a white glyph, lighter while
/// hovered and lighter still while selected. Tab icons and the buttons on the right share it.
enum NotchChipStyle {
    static let diameter: CGFloat = 26
    static let spacing: CGFloat = 8
    static let fill = Color(white: 0.17)
    static let hoverFill = Color(white: 0.24)
    static let selectedFill = Color(white: 0.38)
    static let glyph = Color(white: 0.88)

    /// Point sizes that make mixed symbols read as one size inside the disc.
    static func glyphSize(for symbol: String) -> CGFloat {
        switch symbol {
        case "gearshape", "timer", "faceid", "web.camera": 12.5
        case "list.clipboard", "doc.on.clipboard.fill", "note.text", "eyedropper": 11.5
        case "chart.xyaxis.line", "tray.fill": 11
        default: 12
        }
    }
}

/// A header chip's face: the disc and its glyph, which dims while `isDimmed`.
struct NotchChipFace: View {
    let symbol: String
    var isSelected = false
    var isDimmed = false

    @State private var isHovering = false

    var body: some View {
        Circle()
            .fill(isSelected ? NotchChipStyle.selectedFill : isHovering ? NotchChipStyle.hoverFill : NotchChipStyle.fill)
            .frame(width: NotchChipStyle.diameter, height: NotchChipStyle.diameter)
            .overlay {
                NotchChipGlyph(symbol: symbol, isSelected: isSelected)
                    .opacity(isDimmed ? 0.55 : 1)
            }
            .contentShape(Circle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
    }
}

struct NotchChipGlyph: View {
    let symbol: String
    var isSelected = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: NotchChipStyle.glyphSize(for: symbol), weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : NotchChipStyle.glyph)
    }
}
