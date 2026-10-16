import SwiftUI

/// Atoll's fake spectrum candles: 2 pt wide with 2 pt gaps and 14 pt tall, each scaled
/// vertically about its centre.
struct MediaSpectrumBars: View {
    let scales: [CGFloat]

    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 2
    static let barHeight: CGFloat = 14
    static let restingScale: CGFloat = 0.35

    /// Width the candles occupy: `barCount * 4`.
    static func width(for barCount: Int) -> CGFloat {
        CGFloat(max(barCount, 0)) * (barWidth + barSpacing)
    }

    var body: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(Array(scales.enumerated()), id: \.offset) { _, scale in
                RoundedRectangle(cornerRadius: Self.barWidth / 2)
                    .frame(width: Self.barWidth, height: Self.barHeight)
                    .scaleEffect(x: 1, y: scale, anchor: .center)
            }
        }
        .frame(width: Self.width(for: scales.count), alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// The spectrum as drawn in the closed right wing: a 50-pt rectangle filled with the
/// artwork gradient (or grey), masked by the candles in a `barCount * 4` x 12 box. While
/// playing, every 0.3 s each candle heads linearly to a random height between 35 % and
/// 100 %; paused, they settle at 35 %.
struct MediaSpectrumWing: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings

    static let interval: Duration = .milliseconds(300)

    @State private var scales: [CGFloat] = []

    var body: some View {
        if settings.useMusicVisualizer {
            let count = settings.visualizerBarCount
            Rectangle()
                .fill(fill)
                .frame(width: 50)
                .mask {
                    MediaSpectrumBars(scales: resolvedScales(count: count))
                        .frame(width: MediaSpectrumBars.width(for: count), height: 12)
                }
                .task(id: AnimationKey(playing: manager.isPlaying, count: count)) {
                    await animate(count: count, playing: manager.isPlaying)
                }
        } else {
            // Atoll plays a Lottie loop here; an animated waveform symbol stands in.
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settings.coloredSpectrogram ? manager.avgColor.color : .gray)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: manager.isPlaying)
        }
    }

    private struct AnimationKey: Equatable {
        let playing: Bool
        let count: Int
    }

    private var fill: AnyShapeStyle {
        let base = settings.coloredSpectrogram ? manager.avgColor : .systemGray
        return base.spectrogramStyle(mode: settings.colorExtractionMode)
    }

    private func resolvedScales(count: Int) -> [CGFloat] {
        (0 ..< count).map { scales.indices.contains($0) ? scales[$0] : MediaSpectrumBars.restingScale }
    }

    private func animate(count: Int, playing: Bool) async {
        guard playing else {
            withAnimation(.linear(duration: 0.3)) {
                scales = Array(repeating: MediaSpectrumBars.restingScale, count: count)
            }
            return
        }
        while !Task.isCancelled {
            withAnimation(.linear(duration: 0.3)) {
                scales = (0 ..< count).map { _ in CGFloat.random(in: MediaSpectrumBars.restingScale ... 1) }
            }
            try? await Task.sleep(for: Self.interval)
        }
    }
}
