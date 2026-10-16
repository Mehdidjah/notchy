import AppKit
import SwiftUI

/// Transport button: a 30-pt (or 40-pt for play/pause) hit square whose capsule
/// turns grey on hover, with an optional press nudge/wiggle or a marching skip glyph.
struct MediaHoverButton: View {
    enum Size {
        case medium
        case large

        var side: CGFloat { self == .large ? 40 : 30 }
        var font: Font { self == .large ? .largeTitle : .body }
        var glyphPointSize: CGFloat {
            NSFont.preferredFont(forTextStyle: self == .large ? .largeTitle : .body).pointSize
        }
    }

    enum PressEffect: Equatable {
        case nudge(CGFloat)
        case wiggle(clockwise: Bool)
    }

    var icon: String
    var iconColor: Color = .white
    var size: Size = .medium
    var pressEffect: PressEffect?
    /// When set, draws the animated skip glyph instead of `icon`.
    var skipDirection: MusicManager.SkipDirection?
    /// A changing token plays the press effect without a click (horizontal swipes).
    var externalTrigger: Int?
    var externalEffect: PressEffect?
    var accessibilityTitle: String = ""
    var action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var wiggleToken = 0
    @State private var skipToken = 0
    @State private var lastExternalTrigger: Int?

    var body: some View {
        Button {
            playPressEffect(nil)
            action()
        } label: {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size.side, height: size.side)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size.side, height: size.side)
                        .overlay { glyph }
                }
        }
        .buttonStyle(.plain)
        .offset(x: pressOffset)
        .rotationEffect(.degrees(wiggleAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTrigger) { _, token in
            guard let token, token != lastExternalTrigger else { return }
            lastExternalTrigger = token
            playPressEffect(externalEffect)
        }
        .accessibilityLabel(accessibilityTitle.isEmpty ? icon : accessibilityTitle)
    }

    @ViewBuilder
    private var glyph: some View {
        if let skipDirection {
            MediaSkipTrackGlyph(direction: skipDirection, size: size.glyphPointSize, trigger: skipToken)
                .foregroundStyle(iconColor)
        } else if case .wiggle = pressEffect {
            if #available(macOS 15.0, *) {
                symbol.symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
            } else {
                symbol
            }
        } else {
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: icon)
            .foregroundStyle(iconColor)
            .contentTransition(.symbolEffect)
            .font(size.font)
    }

    private func playPressEffect(_ override: PressEffect?) {
        if skipDirection != nil {
            skipToken += 1
        }
        guard let effect = override ?? pressEffect else { return }
        switch effect {
        case .nudge(let amount):
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressOffset = amount
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let clockwise):
            wiggleToken += 1
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                wiggleAngle = clockwise ? 10 : -10
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    wiggleAngle = 0
                }
            }
        }
    }
}

/// Apple's skip animation: three triangles march one step in the direction of travel, the
/// leading one fading out and a spare fading in behind, so rapid presses chain.
struct MediaSkipTrackGlyph: View {
    let direction: MusicManager.SkipDirection
    let size: CGFloat
    /// Increment to play one step.
    let trigger: Int

    /// Triangle size relative to the nominal point size, so the resting pair matches
    /// `forward.fill`.
    static let glyphSizeRatio: CGFloat = 0.88
    /// Distance between neighbouring triangles, and the travel of one press.
    static let stepRatio: CGFloat = 0.52
    static let travelDuration: TimeInterval = 0.26

    @State private var phase: CGFloat = 0

    var body: some View {
        MediaSkipArrows(phase: phase, glyphSize: size * Self.glyphSizeRatio, step: size * Self.stepRatio)
            .frame(width: size * 1.5, height: size)
            .rotationEffect(direction == .forward ? .zero : .degrees(180))
            .onChange(of: trigger) { oldValue, newValue in
                let presses = max(newValue - oldValue, 1)
                withAnimation(.easeOut(duration: Self.travelDuration)) {
                    phase += CGFloat(presses)
                }
            }
    }
}

/// The triangles positioned from an accumulated phase; `Animatable` so SwiftUI interpolates
/// the phase itself rather than identical start and end frames.
private struct MediaSkipArrows: View, @preconcurrency Animatable {
    var phase: CGFloat
    let glyphSize: CGFloat
    let step: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    private var cycle: CGFloat { phase - phase.rounded(.down) }

    var body: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { slot in
                Image(systemName: "play.fill")
                    .font(.system(size: glyphSize, weight: .medium))
                    .opacity(opacity(for: slot))
                    .offset(x: (CGFloat(slot) - 1.5 + cycle) * step)
            }
        }
    }

    private func opacity(for slot: Int) -> Double {
        switch slot {
        case 2: Double(1 - cycle)
        case 0: Double(cycle)
        default: 1
        }
    }
}
