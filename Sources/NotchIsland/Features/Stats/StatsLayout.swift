import CoreGraphics

/// Grid arithmetic for the stats tab: how the enabled cards split into rows, how much
/// taller the island must be for a second row, and how a card shrinks when it gets less
/// height than it was designed for.
enum StatsLayout {
    /// Points around the whole grid.
    static let gridPadding: CGFloat = 12
    /// Horizontal gap between cards in a row.
    static let columnSpacing: CGFloat = 8
    /// Vertical gap between the two rows.
    static let rowSpacing: CGFloat = 12
    /// Inset inside a card.
    static let cardPadding: CGFloat = 8
    static let cardCornerRadius: CGFloat = 8
    /// Height reserved for the second row of cards.
    static let secondRowContentHeight: CGFloat = 120
    /// Extra island height when a second row is shown: the row plus the gap above it.
    static let secondRowExtraHeight: CGFloat = secondRowContentHeight + rowSpacing
    /// The open island's base content height for this tab (`NotchTab.stats.openHeight`).
    static let baseOpenHeight: CGFloat = 200
    /// Cards beyond this many wrap onto a second row.
    static let maximumCardsPerRow = 3

    static func rowCount(forCardCount count: Int) -> Int {
        if count <= 0 { return 0 }
        return count <= maximumCardsPerRow ? 1 : 2
    }

    /// Splits the cards into rows: up to three in one row, four as 2 + 2, five as 3 + 2.
    static func rows<T>(for cards: [T]) -> [[T]] {
        switch cards.count {
        case 0: return []
        case 1...maximumCardsPerRow: return [cards]
        case 4: return [Array(cards[0..<2]), Array(cards[2..<4])]
        default: return [Array(cards[0..<3]), Array(cards[3...])]
        }
    }

    /// How much taller than its base height the open island should be for this many cards.
    static func extraOpenHeight(forCardCount count: Int) -> CGFloat {
        rowCount(forCardCount: count) >= 2 ? secondRowExtraHeight : 0
    }

    /// The tab's open height for this many cards: 200 for one row, 332 for two.
    static func openHeight(forCardCount count: Int) -> CGFloat {
        baseOpenHeight + extraOpenHeight(forCardCount: count)
    }
}

/// How tall a card's graph is and whether it has room for the hover hint, given the height
/// the grid actually received. At full size a card is 105 pt: 8 padding, a 13-pt header,
/// an 18-pt value line, a 36-pt graph and a 13-pt hint with 3-pt gaps.
struct StatsCardSizing: Equatable, Sendable {
    static let fullGraphHeight: CGFloat = 36
    static let minimumGraphHeight: CGFloat = 10
    /// Padding, header line, value line, hint line and the gaps between them.
    static let chromeHeight: CGFloat = 69
    /// The hint line and the gap above it.
    static let hintHeight: CGFloat = 16
    /// What a card measures when nothing is squeezed.
    static let naturalHeight: CGFloat = chromeHeight + fullGraphHeight

    static let full = StatsCardSizing(graphHeight: fullGraphHeight, showsHint: true)

    let graphHeight: CGFloat
    let showsHint: Bool

    init(graphHeight: CGFloat, showsHint: Bool) {
        self.graphHeight = graphHeight
        self.showsHint = showsHint
    }

    /// `contentHeight` is the whole grid area including its padding; zero (not laid out yet)
    /// keeps the full size. When a row's share is short, the hint goes first, then the graph
    /// shrinks down to 10 pt.
    init(contentHeight: CGFloat, rowCount: Int) {
        guard contentHeight > 0 else {
            self = .full
            return
        }
        let rows = CGFloat(max(1, rowCount))
        let budget = (contentHeight - StatsLayout.gridPadding * 2 - StatsLayout.rowSpacing * (rows - 1)) / rows
        if budget >= Self.naturalHeight {
            self = .full
        } else {
            showsHint = false
            graphHeight = min(
                Self.fullGraphHeight,
                max(Self.minimumGraphHeight, budget - (Self.chromeHeight - Self.hintHeight))
            )
        }
    }
}
