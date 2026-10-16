import AppKit
import SwiftUI

private struct MediaMarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Text that scrolls left in a loop when it is wider than its frame: two copies 20 pt apart,
/// a pause of `minDuration`, a linear run at 30 pt/s to the second copy, a snap back, repeat.
/// Short text sits still.
struct MediaMarqueeText: View {
    let text: String
    var font: Font = .body
    var nsFont: NSFont.TextStyle = .body
    var textColor: Color = .primary
    var minDuration: Double = 3
    var frameWidth: CGFloat = 200

    static let loopSpacing: CGFloat = 20
    /// Scrolling speed in points per second.
    static let speed: CGFloat = 30

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScrolling: Bool { textWidth > frameWidth }

    /// Width of one copy recovered from the measured pair.
    static func singleWidth(fromLoopWidth width: CGFloat) -> CGFloat {
        max(0, (width - loopSpacing) / 2)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: Self.loopSpacing) {
                Text(text)
                Text(text).opacity(needsScrolling ? 1 : 0)
            }
            .font(font)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: MediaMarqueeWidthKey.self, value: proxy.size.width)
            })
            .onPreferenceChange(MediaMarqueeWidthKey.self) { width in
                textWidth = Self.singleWidth(fromLoopWidth: width)
            }
        }
        .frame(width: max(0, frameWidth), alignment: .leading)
        .clipped()
        .frame(height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
        .task(id: LoopKey(text: text, scrolls: needsScrolling, width: textWidth, minDuration: minDuration)) {
            await runLoop()
        }
    }

    private struct LoopKey: Equatable {
        let text: String
        let scrolls: Bool
        let width: CGFloat
        let minDuration: Double
    }

    private func runLoop() async {
        resetOffset()
        try? await Task.sleep(for: .milliseconds(100))
        guard needsScrolling else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(minDuration))
            guard !Task.isCancelled else { return }
            let duration = Double(textWidth / Self.speed)
            withAnimation(.linear(duration: duration)) {
                offset = -(textWidth + Self.loopSpacing)
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            resetOffset()
        }
    }

    private func resetOffset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
        }
    }
}

/// The rounded "E" chip shown after explicit titles.
struct MediaExplicitBadge: View {
    var fontSize: CGFloat = 9
    var height: CGFloat = 14

    var body: some View {
        Text("E")
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, max(4, height * 0.2))
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: max(4, height * 0.28), style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .fixedSize()
            .accessibilityLabel("Explicit")
    }
}

/// A title that marquees only when it overflows, followed by the explicit badge when the
/// track is explicit; the badge's width is reserved out of `frameWidth`.
struct MediaTitleMarquee: View {
    let text: String
    let isExplicit: Bool
    var font: Font = .body
    var nsFont: NSFont.TextStyle = .body
    var textColor: Color = .primary
    var minDuration: Double = 3
    var frameWidth: CGFloat = 200
    var badgeHeight: CGFloat?

    private static let badgeSpacing: CGFloat = 6

    private var resolvedBadgeHeight: CGFloat {
        badgeHeight ?? max(12, NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.12)
    }

    private var reservedBadgeWidth: CGFloat {
        guard isExplicit else { return 0 }
        return resolvedBadgeHeight * 1.7 + Self.badgeSpacing
    }

    private var titleFrameWidth: CGFloat { max(0, frameWidth - reservedBadgeWidth) }

    private var measuredWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.preferredFont(forTextStyle: nsFont)]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    var body: some View {
        HStack(spacing: Self.badgeSpacing) {
            if measuredWidth > titleFrameWidth {
                MediaMarqueeText(
                    text: text,
                    font: font,
                    nsFont: nsFont,
                    textColor: textColor,
                    minDuration: minDuration,
                    frameWidth: titleFrameWidth
                )
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if isExplicit {
                MediaExplicitBadge(fontSize: max(8, resolvedBadgeHeight * 0.6), height: resolvedBadgeHeight)
            }
        }
        .frame(width: max(0, frameWidth), alignment: .leading)
    }
}
