import AppKit
import SwiftUI

/// Measures text with the same AppKit fonts the views draw with, so widths can be known
/// before layout (the closed-notch wings are sized from them).
enum TimerTextMeasurer {
    static func width(of text: String, font: NSFont) -> CGFloat {
        let measured = NSAttributedString(string: text, attributes: [.font: font]).size().width
        return ceil(measured)
    }

    static func systemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Fully monospaced, matching SwiftUI's `.monospaced` design, so separators measure
    /// the same as digits and "1:00:00" is not clipped.
    static func monospacedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

/// A single line that scrolls sideways when it does not fit. Two copies of the text sit
/// 20 pt apart; after a pause the pair glides left at 30 pt/s by one copy's width, snaps
/// back without animating and repeats. Text that fits never moves.
struct TimerMarqueeText: View {
    static let loopGap: CGFloat = 20
    static let pointsPerSecond: CGFloat = 30

    let text: String
    let font: Font
    let measuringFont: NSFont
    let color: Color
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var offset: CGFloat = 0
    @State private var loopTask: Task<Void, Never>?

    private var textWidth: CGFloat {
        TimerTextMeasurer.width(of: text, font: measuringFont)
    }

    private var needsScrolling: Bool {
        textWidth > frameWidth
    }

    var body: some View {
        HStack(spacing: Self.loopGap) {
            Text(text)
            if needsScrolling {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: measuringFont.pointSize * 1.3)
        .onAppear(perform: restartLoop)
        .onChange(of: text) { _, _ in restartLoop() }
        .onChange(of: frameWidth) { _, _ in restartLoop() }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
        .accessibilityLabel(text)
    }

    private func restartLoop() {
        loopTask?.cancel()
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { offset = 0 }
        guard needsScrolling else { return }
        let distance = textWidth + Self.loopGap
        let travel = Double(distance / Self.pointsPerSecond)
        let pause = minDuration
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: travel)) { offset = -distance }
                try? await Task.sleep(for: .seconds(travel))
                guard !Task.isCancelled else { return }
                withTransaction(snap) { offset = 0 }
            }
        }
    }
}
