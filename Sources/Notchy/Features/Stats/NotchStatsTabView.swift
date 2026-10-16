import SwiftUI

/// Stats tab content: up to five metric cards (CPU, Memory, GPU, Network, Disk) in one row
/// for three or fewer, two rows for four or five; clicking a card swaps the grid for that
/// metric's detail panel. Sampling runs only while this view is on screen: it starts half a
/// second after the tab appears and stops shortly after it goes away.
struct NotchStatsTabView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var manager = StatsManager.shared
    @ObservedObject private var settings = StatsSettings.shared
    @State private var detailMetric: StatsMetric?

    var body: some View {
        let metrics = settings.enabledMetrics
        ZStack {
            if let detailMetric, metrics.contains(detailMetric) {
                StatsDetailView(metric: detailMetric, manager: manager) {
                    withAnimation(.easeInOut(duration: 0.25)) { self.detailMetric = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if metrics.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                grid(for: metrics)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: metrics.count)
        .animation(.easeInOut(duration: 0.25), value: detailMetric)
        .onAppear {
            manager.updateMonitoringState(notchIsOpen: true, statsTabSelected: true)
        }
        .onDisappear {
            // Either the island closed or another tab took over; the manager picks the
            // matching stop delay (3 s after a close, 0.1 s after a tab switch).
            manager.updateMonitoringState(
                notchIsOpen: model.state.showsShelfContent,
                statsTabSelected: model.selectedTab == .stats
            )
        }
    }

    /// Rows of equal-width cards, centred in whatever height the island gives the tab.
    private func grid(for metrics: [StatsMetric]) -> some View {
        GeometryReader { proxy in
            let rows = StatsLayout.rows(for: metrics)
            let sizing = StatsCardSizing(contentHeight: proxy.size.height, rowCount: rows.count)
            VStack(spacing: StatsLayout.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: StatsLayout.columnSpacing) {
                        ForEach(row) { metric in
                            StatsMetricCard(
                                metric: metric,
                                content: manager.cardContent(for: metric),
                                sizing: sizing
                            ) {
                                withAnimation(.easeInOut(duration: 0.25)) { detailMetric = metric }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(StatsLayout.gridPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Graphs Enabled")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable graph visibility in Settings → Stats to view performance data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
