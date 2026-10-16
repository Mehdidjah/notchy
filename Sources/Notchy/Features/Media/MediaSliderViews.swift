import SwiftUI

/// The open player's progress slider with elapsed and total time under it.
///
/// Driven by a 30-fps `TimelineView` in the parent: each tick re-derives the position from
/// the playback anchor without animation, unless the user is dragging or has just let go
/// (until a reading newer than the drag arrives).
struct MediaMusicSlider: View {
    @Binding var sliderValue: Double
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let duration: Double
    let currentDate: Date
    let timestampDate: Date
    let isPlaying: Bool
    let isLiveStream: Bool
    let tint: Color
    let labelColor: Color
    let position: (Date) -> Double
    let onSeek: (Double) -> Void

    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14

    private var hasUsableDuration: Bool { MediaPlaybackMath.isUsableDuration(duration) }
    private var frameHeight: CGFloat { max(restingTrackHeight, draggingTrackHeight) }

    var body: some View {
        Group {
            if isLiveStream {
                MediaLiveStreamIndicator(tint: tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: frameHeight)
            } else {
                VStack(spacing: 6) {
                    track
                        .frame(height: frameHeight)
                    HStack {
                        Text(MediaPlaybackMath.timeString(sliderValue))
                        Spacer()
                        Text(hasUsableDuration ? MediaPlaybackMath.timeString(duration) : MediaPlaybackMath.unknownTime)
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(labelColor)
                }
            }
        }
        .onAppear {
            guard !isLiveStream, !dragging else { return }
            setWithoutAnimation(position(Date()))
        }
        .onChange(of: currentDate) { _, date in
            guard !isLiveStream, !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setWithoutAnimation(position(date))
        }
        .onChange(of: isPlaying) { _, playing in
            if !playing, !dragging { setWithoutAnimation(position(Date())) }
        }
        .onChange(of: isLiveStream) { _, live in
            if live { sliderValue = 0 }
        }
    }

    @ViewBuilder
    private var track: some View {
        if hasUsableDuration {
            MediaCustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: tint,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onSeek,
                restingTrackHeight: restingTrackHeight,
                draggingTrackHeight: draggingTrackHeight
            )
        } else {
            // No duration yet: an inert track filled against a surrogate length.
            let current = max(0, sliderValue)
            let surrogate = max(1, current * 2)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule().fill(tint).frame(width: max(1, proxy.size.width) * min(current / surrogate, 1))
                }
                .frame(height: restingTrackHeight)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .transaction { $0.disablesAnimations = true }
        }
    }

    private func setWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }
}

/// A grey track with a filled part that swells from 8 to 14 pt while dragged; a drag
/// anywhere on it scrubs, and the seek is sent on release.
struct MediaCustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight = dragging ? draggingTrackHeight : restingTrackHeight
            let span = range.upperBound - range.lowerBound
            let progress = span == 0 ? 0 : (value - range.lowerBound) / span
            let filled = min(max(progress, 0), 1) * max(1, width)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: trackHeight)
                    .clipShape(RoundedRectangle(cornerRadius: trackHeight / 2))
                    .transaction { $0.disablesAnimations = true }
                Rectangle()
                    .fill(color)
                    .frame(width: filled, height: trackHeight)
                    .clipShape(RoundedRectangle(cornerRadius: trackHeight / 2))
                    .transaction { $0.disablesAnimations = true }
            }
            .frame(height: max(restingTrackHeight, draggingTrackHeight), alignment: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation { dragging = true }
                        guard width > 0 else { return }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * span
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.bouncy.speed(1.4), value: dragging)
        }
    }
}

/// In place of a progress bar on a stream: two thin rules fading away from a plain "LIVE".
struct MediaLiveStreamIndicator: View {
    let tint: Color
    var labelSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 10) {
            rule(towards: .leading)
            Text("LIVE")
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(tint)
                .fixedSize()
            rule(towards: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Live stream")
    }

    private func rule(towards edge: UnitPoint) -> some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(
                colors: [tint.opacity(0.5), tint.opacity(0.16)],
                startPoint: edge == .leading ? .trailing : .leading,
                endPoint: edge
            ))
            .frame(height: 3)
    }
}
