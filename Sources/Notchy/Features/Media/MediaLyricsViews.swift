import AppKit
import SwiftUI

/// Three music notes marking an instrumental stretch.
struct MediaInstrumentalNotes: View {
    var fontSize: CGFloat = 12
    var weight: Font.Weight = .semibold

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Image(systemName: "music.note")
                    .font(.system(size: fontSize, weight: weight))
            }
        }
        .accessibilityLabel("Instrumental")
    }
}

/// The current lyric under the artist: 12-pt marquee at 70 % white, or notes during an
/// instrumental break; lines slide up and fade as they change.
struct MediaInlineLyricLine: View {
    @ObservedObject var manager: MusicManager
    let width: CGFloat

    private static let transition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    )

    var body: some View {
        let line = manager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBreak = manager.isInInstrumentalBreak
        ZStack(alignment: .leading) {
            if isBreak {
                MediaInstrumentalNotes(fontSize: 10, weight: .regular)
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(Self.transition)
            } else if !line.isEmpty {
                MediaMarqueeText(
                    text: line,
                    font: .system(size: 12, weight: .regular),
                    nsFont: .headline,
                    textColor: .white.opacity(0.7),
                    minDuration: 0.35,
                    frameWidth: width
                )
                .id(line)
                .transition(Self.transition)
            }
        }
        .padding(.top, 2)
        .animation(.easeInOut(duration: 0.32), value: line)
        .animation(.easeInOut(duration: 0.32), value: isBreak)
    }
}

/// Atoll's side lyrics panel: a tinted "Lyrics" header over a scrolling list whose current
/// line is lit word by word (or with the chosen highlight style), on a 30 % black card with
/// 4-pt corners. While the pointer is over it, scrolling the lyrics never closes the island.
struct MediaLyricsSidePanel: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings

    private var tint: Color {
        settings.playerColorTinting ? manager.avgColor.ensuringMinimumBrightness(0.6).color : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Lyrics")
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            MediaSyncedLyricsList(
                manager: manager,
                palette: MediaLyricPalette(
                    sung: .white,
                    unsung: tint.opacity(0.55),
                    idle: .white.opacity(0.5),
                    tint: tint
                ),
                highlightStyle: settings.lyricHighlightStyle
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { MediaInteractionState.shared.setSuppressesCloseGesture($0) }
        .onDisappear { MediaInteractionState.shared.setSuppressesCloseGesture(false) }
    }
}

/// Colours of the lyric list: sung text, the unsung rest of the current line, other lines,
/// and the accent the gradient style runs from.
struct MediaLyricPalette: Equatable {
    var sung: Color
    var unsung: Color
    var idle: Color
    var tint: Color
}

/// Scrolling lyrics that keep the current line centred.
private struct MediaSyncedLyricsList: View {
    @ObservedObject var manager: MusicManager
    let palette: MediaLyricPalette
    let highlightStyle: MediaLyricHighlightStyle

    private static let fontSize: CGFloat = 14
    private static let instrumentalFontSize: CGFloat = 12
    private static let lineSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 4

    private enum Row: Identifiable {
        case line(index: Int, text: String)
        case instrumental(index: Int)

        var id: Int {
            switch self {
            case let .line(index, _), let .instrumental(index): index
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if manager.lyricLines.isEmpty {
                    Text(manager.currentLyrics.isEmpty ? "Show lyrics here" : manager.currentLyrics)
                        .font(.system(size: Self.fontSize, weight: .medium))
                        .foregroundStyle(palette.idle)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 30 fps while playing so the highlight follows the singing smoothly.
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !manager.isPlaying)) { timeline in
                        let current = manager.currentLyricIndex
                        let progress = manager.currentLyricSweepProgress(at: timeline.date)
                        LazyVStack(alignment: .leading, spacing: Self.lineSpacing) {
                            ForEach(rows) { row in
                                rowView(row, isCurrent: row.id == current, progress: progress)
                                    .padding(.horizontal, Self.horizontalPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(row.id)
                            }
                        }
                        .padding(.vertical, Self.verticalPadding)
                    }
                }
            }
            .scrollIndicators(.never)
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: manager.currentLyricIndex) { _, _ in scroll(proxy, animated: true) }
            .onChange(of: manager.lyricLines) { _, _ in scroll(proxy, animated: false) }
        }
    }

    /// Lines, with a note row for each blank stretch of five seconds or more, and for a
    /// long intro (keyed -1, the index before the first line).
    private var rows: [Row] {
        let lines = manager.lyricLines
        var rows: [Row] = []
        if let first = lines.first, first.isTimed, first.timestamp >= MediaLyricsEngine.instrumentalBreakThreshold {
            rows.append(.instrumental(index: -1))
        }
        for (index, line) in lines.enumerated() {
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let end = index + 1 < lines.count ? lines[index + 1].timestamp : manager.songDuration
                if line.isTimed, end - line.timestamp >= MediaLyricsEngine.instrumentalBreakThreshold {
                    rows.append(.instrumental(index: index))
                }
                continue
            }
            rows.append(.line(index: index, text: line.text))
        }
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row, isCurrent: Bool, progress: Double) -> some View {
        switch row {
        case let .line(_, text):
            MediaSweptLyricText(
                text: text,
                fontSize: Self.fontSize,
                weight: isCurrent ? .semibold : .regular,
                progress: progress,
                isCurrent: isCurrent,
                palette: palette,
                style: highlightStyle
            )
        case .instrumental:
            MediaInstrumentalNotes(fontSize: Self.instrumentalFontSize, weight: isCurrent ? .semibold : .regular)
                .mediaLyricSweep(progress: progress, isCurrent: isCurrent, sung: palette.sung, unsung: palette.unsung, idle: palette.idle)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        let index = manager.currentLyricIndex
        let ids = rows.map(\.id)
        let target: Int?
        if ids.contains(index) {
            target = index
        } else if index < 0 {
            target = ids.first
        } else {
            target = nil
        }
        guard let target else { return }
        if animated {
            withAnimation(.smooth(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }
}

// MARK: - Sweep

/// The sung-to-unsung gradient: sung colour up to `progress`, unsung after, with a 0.06
/// feather so the boundary reads as singing rather than a wipe.
enum MediaLyricSweep {
    static let feather = 0.06

    static func gradient(progress: Double, sung: Color, unsung: Color) -> LinearGradient {
        let p = min(max(progress, 0), 1)
        return LinearGradient(
            stops: [
                .init(color: sung, location: 0),
                .init(color: sung, location: max(0, p - feather)),
                .init(color: unsung, location: min(1, p + feather)),
                .init(color: unsung, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// How far through one word the line's progress is, given the word's share of the line.
    static func wordProgress(lineProgress: Double, start: Double, end: Double) -> Double {
        let span = end - start
        guard span > 0 else { return lineProgress >= end ? 1 : 0 }
        return min(max((lineProgress - start) / span, 0), 1)
    }

    /// Each word's slice of the line, weighted by its length plus one, in reading order.
    static func wordSlices(in text: String) -> [(word: String, start: Double, end: Double)] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let weights = words.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }
        var cursor = 0.0
        return zip(words, weights).map { word, weight in
            let start = cursor / total
            cursor += weight
            return (word, start, cursor / total)
        }
    }
}

private struct MediaLyricSweepModifier: ViewModifier {
    let progress: Double
    let isCurrent: Bool
    let sung: Color
    let unsung: Color
    let idle: Color

    func body(content: Content) -> some View {
        if isCurrent {
            // Overlay and mask rather than a foreground style: a gradient foreground is
            // resolved per glyph run and would not travel across the text.
            content
                .hidden()
                .overlay { MediaLyricSweep.gradient(progress: progress, sung: sung, unsung: unsung) }
                .mask { content }
        } else {
            content.foregroundStyle(idle)
        }
    }
}

extension View {
    /// Paints the view with the lyric sweep when it is the current line, or dims it.
    func mediaLyricSweep(progress: Double, isCurrent: Bool, sung: Color, unsung: Color, idle: Color) -> some View {
        modifier(MediaLyricSweepModifier(progress: progress, isCurrent: isCurrent, sung: sung, unsung: unsung, idle: idle))
    }
}

/// A lyric line in the chosen highlight style. Sweep lays the words out one by one so the
/// highlight travels in reading order even across a wrapped line; Gradient paints the
/// current line with one fixed tint-white-tint gradient; Solid paints it flat white.
struct MediaSweptLyricText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let progress: Double
    let isCurrent: Bool
    let palette: MediaLyricPalette
    let style: MediaLyricHighlightStyle

    var body: some View {
        switch style {
        case .sweep: sweptLine
        case .gradient: gradientLine
        case .solid: solidLine
        }
    }

    private var font: Font { .system(size: fontSize, weight: weight) }

    private var gradientLine: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                isCurrent
                    ? AnyShapeStyle(LinearGradient(
                        colors: [palette.tint, palette.sung, palette.tint.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    : AnyShapeStyle(palette.idle)
            )
    }

    private var solidLine: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isCurrent ? palette.sung : palette.idle)
    }

    private var sweptLine: some View {
        let layout = MediaLyricWordCache.layout(for: text, fontSize: fontSize, weight: weight)
        return MediaWordFlowLayout(spacing: layout.spaceWidth, lineSpacing: fontSize * 0.28) {
            ForEach(Array(layout.words.enumerated()), id: \.offset) { _, word in
                let wordProgress = MediaLyricSweep.wordProgress(lineProgress: progress, start: word.start, end: word.end)
                Text(word.text)
                    .font(font)
                    .mediaLyricSweep(
                        progress: wordProgress,
                        isCurrent: isCurrent && wordProgress > 0,
                        sung: palette.sung,
                        unsung: palette.unsung,
                        // Words of the current line not reached yet wait in the unsung colour.
                        idle: isCurrent ? palette.unsung : palette.idle
                    )
            }
        }
    }
}

/// Word slices and the face's space width per line, computed once rather than on every
/// frame of the 30 fps timeline.
@MainActor
enum MediaLyricWordCache {
    struct Word {
        let text: String
        let start: Double
        let end: Double
    }

    struct Layout {
        let words: [Word]
        let spaceWidth: CGFloat
    }

    private static var cache: [String: Layout] = [:]
    private static let limit = 400

    static func layout(for text: String, fontSize: CGFloat, weight: Font.Weight) -> Layout {
        let key = "\(text)|\(fontSize)|\(weight)"
        if let cached = cache[key] { return cached }
        let words = MediaLyricSweep.wordSlices(in: text).map { Word(text: $0.word, start: $0.start, end: $0.end) }
        let font = NSFont.systemFont(ofSize: fontSize, weight: nsWeight(weight))
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let layout = Layout(words: words, spaceWidth: space)
        if cache.count >= limit { cache.removeAll() }
        cache[key] = layout
        return layout
    }

    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

/// Wraps words the way text wraps: left to right, a new row when the next word would
/// overflow. Measures and places against the same width so rows never spill.
struct MediaWordFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    private func wrapWidth(_ proposal: ProposedViewSize) -> CGFloat {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0)).width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = wrapWidth(proposal)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = min(wrapWidth(proposal), bounds.width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
