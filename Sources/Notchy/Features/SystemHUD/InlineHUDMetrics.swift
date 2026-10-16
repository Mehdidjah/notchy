import CoreGraphics

/// Column sizes of Atoll's `InlineHUD`, and how they map onto the host's wings.
///
/// Atoll draws the inline HUD as `HStack { info ; black (closedWidth - 20) ; trailing }` with
/// the stack's default 8-pt spacing, so the gap between the two content columns is exactly
/// `closedWidth - 4` and does not grow on hover. The host draws its own black centre of
/// `context.centerWidth` (which does grow on hover), so the wing widths are trimmed by half the
/// difference: the island's total width, and where each column's content starts and ends,
/// then match Atoll to the point. Content keeps Atoll's own column width and may overlap the
/// host's centre by those few points, which is where Atoll draws it too.
enum InlineHUDMetrics {
    enum Content: Equatable, Sendable {
        /// Volume or microphone: icon and label, level bar or state text.
        case level
        /// Caps Lock: the glyph, with an optional "Caps Lock" label on the right.
        case capsLock(showsLabel: Bool)
    }

    struct Columns: Equatable, Sendable {
        var info: CGFloat
        var trailing: CGFloat
    }

    /// Atoll `baseInfoWidth` / minimum for volume, brightness, backlight and mic.
    static let levelInfoWidth: CGFloat = 92
    static let levelInfoMinimum: CGFloat = 88
    static let levelTrailingWidth: CGFloat = 92
    static let levelTrailingMinimum: CGFloat = 90
    /// Caps Lock without its label: a narrow glyph column and no trailing column.
    static let capsLockIconInfoWidth: CGFloat = 56
    static let capsLockIconInfoMinimum: CGFloat = 44
    static let capsLockLabelTrailingWidth: CGFloat = 88
    static let capsLockLabelTrailingMinimum: CGFloat = 72

    /// Default spacing of Atoll's three-column `HStack`.
    static let columnSpacing: CGFloat = 8
    /// Atoll's black centre is the closed notch width minus this.
    static let centreInset: CGFloat = 20
    static let trailingPadding: CGFloat = 4
    static let iconSize = CGSize(width: 20, height: 15)
    static let iconLabelSpacing: CGFloat = 5

    /// Atoll's `infoWidth` and `trailingWidth`, widened by half the swipe progress.
    static func atollColumns(_ content: Content, gestureProgress: CGFloat) -> Columns {
        let swipe = max(0, gestureProgress) / 2
        switch content {
        case .level:
            return Columns(
                info: max(levelInfoWidth + swipe, levelInfoMinimum),
                trailing: max(levelTrailingWidth + swipe, levelTrailingMinimum)
            )
        case .capsLock(let showsLabel):
            let info = showsLabel
                ? max(levelInfoWidth + swipe, levelInfoMinimum)
                : max(capsLockIconInfoWidth + swipe, capsLockIconInfoMinimum)
            let trailing = showsLabel
                ? max(capsLockLabelTrailingWidth + swipe, capsLockLabelTrailingMinimum)
                : swipe
            return Columns(info: info, trailing: trailing)
        }
    }

    /// The black gap Atoll leaves between the two content columns.
    static func atollGap(notchWidth: CGFloat) -> CGFloat {
        max(0, notchWidth - centreInset) + 2 * columnSpacing
    }

    /// Width of Atoll's whole inline row, before the island's side padding.
    static func atollRowWidth(_ content: Content, context: ClosedActivityContext) -> CGFloat {
        let columns = atollColumns(content, gestureProgress: context.gestureProgress)
        return columns.info + atollGap(notchWidth: context.notchWidth) + columns.trailing
    }

    /// Wing widths for the host's layout that reproduce Atoll's total width and edges.
    static func wingWidths(_ content: Content, context: ClosedActivityContext) -> Columns {
        let columns = atollColumns(content, gestureProgress: context.gestureProgress)
        let excess = context.centerWidth - atollGap(notchWidth: context.notchWidth)
        var left = columns.info - excess / 2
        var right = columns.trailing - excess / 2
        if right < 0 {
            left += right
            right = 0
        }
        if left < 0 {
            right = max(0, right + left)
            left = 0
        }
        return Columns(info: left, trailing: right)
    }
}
