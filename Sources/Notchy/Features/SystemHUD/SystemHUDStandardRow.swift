import SwiftUI

/// Standard-style system-event row, for the sneak
/// peeks this feature sends when the inline style is off: a large glyph 14 pt from a level
/// bar and percentage, "muted" in grey at zero, or the microphone's state.
///
/// The island draws sneak peeks itself; this view is offered for its sneak-peek row so the
/// volume row matches this design (see the integration request). Place it with this padding:
/// bottom 10, leading 4, trailing 8.
struct SystemHUDStandardRow: View {
    let peek: SneakPeek
    /// Level set by dragging the bar; the bar writes its bound value, so the fill follows
    /// the pointer until the next event replaces the peek.
    @State private var draggedLevel: CGFloat?

    /// Whether this row knows how to draw `peek`.
    static func handles(_ peek: SneakPeek) -> Bool {
        peek.kind == .volume || isMicrophone(peek)
    }

    private static func isMicrophone(_ peek: SneakPeek) -> Bool {
        peek.kind == .generic && peek.systemImage.hasPrefix("mic")
    }

    private var level: CGFloat {
        draggedLevel ?? CGFloat(peek.level ?? 0)
    }

    var body: some View {
        HStack(spacing: 14) {
            glyph
            section
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Inherits the default body font and draws its glyphs at the large scale.
        .font(.body)
        .imageScale(.large)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .onChange(of: peek.id) { _, _ in draggedLevel = nil }
    }

    /// Volume glyphs sit on the leading edge of their 20 x 15 box, the microphone is centred.
    private var glyph: some View {
        let symbol = peek.kind == .volume
            ? SystemHUDPresenter.speakerSymbolName(for: level)
            : peek.systemImage
        return Image(systemName: symbol)
            .contentTransition(.interpolate)
            .frame(
                width: InlineHUDMetrics.iconSize.width,
                height: InlineHUDMetrics.iconSize.height,
                alignment: peek.kind == .volume ? .leading : .center
            )
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var section: some View {
        if peek.kind == .volume {
            let isMuted = level <= 0
            Group {
                if isMuted {
                    Text("muted")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                        .contentTransition(.numericText())
                } else {
                    HStack(spacing: 8) {
                        SystemHUDProgressBar(
                            value: level,
                            isVolume: true,
                            isInline: false,
                            onDrag: { value in
                                draggedLevel = value
                                SystemHUDManager.shared.userDraggedVolume(to: value)
                            }
                        )
                        SystemHUDPercentageLabel(value: level)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.2), value: isMuted)
        } else {
            Text(peek.title)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .allowsTightening(true)
                .contentTransition(.numericText())
        }
    }
}
