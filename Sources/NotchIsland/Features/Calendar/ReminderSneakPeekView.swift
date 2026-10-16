import AppKit
import SwiftUI

/// Atoll's reminder sneak peek (standard style): an 8 × 12 chip in the calendar colour, then
/// "Title • in 5 min • 10:30" in the reminder colour (red with "• now" in the final seconds),
/// scrolling when it does not fit. The line is recomputed from the live activity's clock, so
/// "in 5 min" ticks down while the peek is up, as it does in Atoll.
///
/// The host draws it in place of its standard row for `SneakPeek.Kind.reminder`, with only the
/// 10-pt bottom inset (Atoll adds no side padding to this row).
struct ReminderSneakPeekView: View {
    @ObservedObject var model: ReminderLiveActivityModel
    /// The request that opened the peek; used if the reminder has already moved on.
    let peek: SneakPeek

    init(peek: SneakPeek, model: ReminderLiveActivityModel = .shared) {
        self.peek = peek
        self.model = model
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(chipColor)
                    .frame(width: 8, height: 12)
                ReminderMarqueeText(
                    text: text,
                    color: textColor,
                    frameWidth: max(0, geometry.size.width - 14)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var entry: ReminderEntry? {
        model.isActivityVisible ? model.activeReminder : nil
    }

    /// The calendar colour lifted to 0.7 luminance; it stays that colour in the final seconds.
    private var chipColor: Color {
        if let entry { return ReminderSchedule.accentColor(entry, critical: false) }
        return peek.tint ?? .gray
    }

    private var textColor: Color {
        if let entry { return model.accent(for: entry) }
        return peek.tint ?? .gray
    }

    private var text: String {
        if let entry {
            return ReminderSchedule.sneakPeekText(entry, now: model.now, window: model.criticalWindow)
        }
        return peek.title
    }
}

/// A single line that loops leftward when wider than `frameWidth`: two copies 20 pt apart,
/// a 1-s hold, a linear run at 30 pt/s until the second copy sits where the first began, an
/// instant snap back, and again. Text that fits stays put. Body font, like Atoll's marquee.
struct ReminderMarqueeText: View {
    let text: String
    let color: Color
    let frameWidth: CGFloat
    var hold: Duration = .seconds(1)

    static let gap: CGFloat = 20
    static let pointsPerSecond: CGFloat = 30

    @State private var pairWidth: CGFloat = 0
    @State private var shift: CGFloat = 0

    /// Width of one copy, from the measured pair (two copies plus the gap).
    private var lineWidth: CGFloat { max(0, (pairWidth - Self.gap) / 2) }
    private var overflows: Bool { lineWidth > frameWidth }

    var body: some View {
        HStack(spacing: Self.gap) {
            Text(text)
            Text(text).opacity(overflows ? 1 : 0)
        }
        .font(.body)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { pairWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in pairWidth = width }
            }
        }
        .offset(x: shift)
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: NSFont.preferredFont(forTextStyle: .body).pointSize * 1.3)
        .task(id: LoopID(text: text, overflows: overflows, lineWidth: lineWidth)) {
            await loop()
        }
    }

    private struct LoopID: Equatable {
        let text: String
        let overflows: Bool
        let lineWidth: CGFloat
    }

    private func loop() async {
        snapBack()
        try? await Task.sleep(for: .milliseconds(100))
        guard overflows else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { break }
            let distance = lineWidth + Self.gap
            let seconds = Double(lineWidth / Self.pointsPerSecond)
            withAnimation(.linear(duration: seconds)) { shift = -distance }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { break }
            snapBack()
        }
        snapBack()
    }

    private func snapBack() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { shift = 0 }
    }
}
