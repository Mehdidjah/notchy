import SwiftUI

/// What a card draws under its header: one value with a sparkline, or an up/down pair with
/// a mirrored graph.
enum StatsCardContent: Equatable {
    case single(value: String, history: [Double])
    case mirrored(upper: String, lower: String, upperHistory: [Double], lowerHistory: [Double])
}

/// One metric card: icon and title, an 18-pt value line, the graph and a hover hint, on a
/// white-8 % rounded rect with a 1-pt border. Hovering lifts the card to 102 % and
/// brightens the border from 18 % to 45 %.
struct StatsMetricCard: View {
    let metric: StatsMetric
    let content: StatsCardContent
    var sizing: StatsCardSizing = .full
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: metric.systemImage)
                        .foregroundStyle(metric.tint)
                        .font(.caption)
                    Text(metric.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.white.opacity(0.8))
                    Spacer(minLength: 0)
                }

                valueLine
                    .frame(height: 18)

                graph
                    .frame(height: sizing.graphHeight)

                if sizing.showsHint {
                    Text("Click for details")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .padding(StatsLayout.cardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: StatsLayout.cardCornerRadius)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: StatsLayout.cardCornerRadius)
                            .stroke(Color.white.opacity(isHovered ? 0.45 : 0.18), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StatsLayout.cardCornerRadius))
            .scaleEffect(isHovered ? 1.02 : 1)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show \(metric.title) details")
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var valueLine: some View {
        switch content {
        case .single(let value, _):
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        case .mirrored(let upper, let lower, _, _):
            HStack(spacing: 6) {
                Text(upper)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(metric.tint)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(lower)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(metric.secondaryTint)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var graph: some View {
        switch content {
        case .single(_, let history):
            StatsSparkline(values: history, color: metric.tint)
        case .mirrored(_, _, let upperHistory, let lowerHistory):
            StatsMirroredGraph(
                upperValues: upperHistory,
                lowerValues: lowerHistory,
                upperColor: metric.tint,
                lowerColor: metric.secondaryTint
            )
        }
    }

    private var accessibilityText: String {
        switch content {
        case .single(let value, _):
            "\(metric.title) \(value)"
        case .mirrored(let upper, let lower, _, _):
            "\(metric.title) \(upper), \(lower)"
        }
    }
}
