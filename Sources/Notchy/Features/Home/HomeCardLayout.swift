import SwiftUI

/// The cards the Home tab can show, in their left-to-right order.
enum HomeCardKind: String, CaseIterable, Sendable {
    case timer
    case media
    case lyrics
    case apps
    case calendar
    case weather
    case mirror
}

/// One card's place in the Home row.
struct HomeCardSlot: Equatable, Sendable {
    let kind: HomeCardKind
    let width: CGFloat
}

/// Lays the Home tab out as one row of cards as tall as the row, 8 pt apart. Fixed cards keep
/// their width; the player, the lyrics and the weather stretch between a minimum and a
/// maximum. When even the minimum widths overflow, cards are left out in `dropOrder`.
enum HomeCardLayout {
    static let spacing: CGFloat = 8
    static let cornerRadius: CGFloat = 18

    struct WidthRange: Equatable, Sendable {
        var minimum: CGFloat
        var ideal: CGFloat
        var maximum: CGFloat

        static func fixed(_ width: CGFloat) -> WidthRange {
            WidthRange(minimum: width, ideal: width, maximum: width)
        }
    }

    static func widthRange(for kind: HomeCardKind, height: CGFloat) -> WidthRange {
        switch kind {
        case .timer, .calendar: .fixed((height * 0.88).rounded())
        case .mirror: .fixed(height.rounded())
        case .apps: .fixed(HomeAppGridMetrics.width(forHeight: height))
        case .media: WidthRange(minimum: height * 1.45, ideal: height * 1.85, maximum: height * 2.6)
        case .lyrics: WidthRange(minimum: height * 1.1, ideal: height * 1.5, maximum: height * 2.4)
        case .weather: WidthRange(minimum: height * 1.15, ideal: height * 1.9, maximum: height * 2.6)
        }
    }

    /// Cards given up, first to last, while the row cannot fit their minimum widths. A running
    /// timer outlasts the other extras; an idle one goes first.
    static func dropOrder(timerRunning: Bool) -> [HomeCardKind] {
        timerRunning
            ? [.apps, .lyrics, .weather, .mirror, .timer, .calendar, .media]
            : [.apps, .timer, .lyrics, .weather, .mirror, .calendar, .media]
    }

    /// Stretchable cards, in the order they give up width to a crowded row.
    static let shrinkOrder: [HomeCardKind] = [.lyrics, .weather, .media]
    /// Stretchable cards, in the order they take up spare width.
    static let growOrder: [HomeCardKind] = [.media, .weather, .lyrics]

    /// `preferredWidths` caps a stretchable card at the width the user chose, within its range.
    static func plan(
        _ kinds: Set<HomeCardKind>,
        width: CGFloat,
        height: CGFloat,
        timerRunning: Bool = false,
        preferredWidths: [HomeCardKind: CGFloat] = [:]
    ) -> [HomeCardSlot] {
        guard width > 0, height > 0 else { return [] }
        var shown = HomeCardKind.allCases.filter(kinds.contains)
        let ranges = Dictionary(uniqueKeysWithValues: shown.map { kind in
            var range = widthRange(for: kind, height: height)
            if let preferred = preferredWidths[kind] {
                range.ideal = min(max(preferred, range.minimum), range.maximum)
                range.maximum = range.ideal
            }
            return (kind, range)
        })
        func rowWidth(_ widthOf: (HomeCardKind) -> CGFloat) -> CGFloat {
            shown.reduce(0) { $0 + widthOf($1) } + spacing * CGFloat(max(0, shown.count - 1))
        }

        let drops = dropOrder(timerRunning: timerRunning)
        while !shown.isEmpty, rowWidth({ ranges[$0]?.minimum ?? 0 }) > width {
            guard let dropped = drops.first(where: shown.contains) else { break }
            shown.removeAll { $0 == dropped }
        }

        var widths = Dictionary(uniqueKeysWithValues: shown.map { ($0, ranges[$0]?.ideal ?? 0) })
        var overflow = rowWidth { widths[$0] ?? 0 } - width
        if overflow > 0 {
            for kind in shrinkOrder where overflow > 0 {
                guard let current = widths[kind], let range = ranges[kind] else { continue }
                let cut = min(current - range.minimum, overflow)
                widths[kind] = current - cut
                overflow -= cut
            }
        } else {
            var spare = -overflow
            for kind in growOrder where spare > 0 {
                guard let current = widths[kind], let range = ranges[kind] else { continue }
                let added = min(range.maximum - current, spare)
                widths[kind] = current + added
                spare -= added
            }
        }
        return shown.map { HomeCardSlot(kind: $0, width: (widths[$0] ?? 0).rounded(.down)) }
    }
}

/// Colours of the Home cards.
enum HomeCardPalette {
    static let fillTop = Color(white: 0.13)
    static let fillBottom = Color(white: 0.215)
    static let rimTop = Color.white.opacity(0.04)
    static let rimBottom = Color.white.opacity(0.13)
    static let track = Color(white: 0.27)
    static let primaryText = Color(white: 0.93)
    static let secondaryText = Color(white: 0.6)
    static let orange = Color(red: 1, green: 0.62, blue: 0.04)
    static let red = Color(red: 1, green: 0.27, blue: 0.23)
    static let pink = Color(red: 1, green: 0.42, blue: 0.58)
}

/// A card's face: a dark grey fill that lightens towards the bottom, under a hairline rim
/// that is brightest along the bottom edge.
struct HomeCardBackground: View {
    var cornerStyle: RoundedCornerStyle = .continuous

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: cornerStyle)
        shape
            .fill(LinearGradient(
                colors: [HomeCardPalette.fillTop, HomeCardPalette.fillBottom],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [HomeCardPalette.rimTop, HomeCardPalette.rimBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

/// Content on a card face, padded and clipped to the card's corners.
struct HomeCard<Content: View>: View {
    var padding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HomeCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: .continuous))
    }
}

/// A small text button on a faint capsule, for a card's one action.
struct HomeCapsuleButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HomeCardPalette.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// A round card button: a glyph on a disc of its own tint, or white glyph on a faint disc.
struct HomeRoundButton: View {
    let symbol: String
    var tint: Color?
    var diameter: CGFloat = 28
    var glyphSize: CGFloat = 11
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(tint ?? .white)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(tint.map { $0.opacity(isHovering ? 0.4 : 0.28) } ?? Color.white.opacity(isHovering ? 0.26 : 0.16))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
