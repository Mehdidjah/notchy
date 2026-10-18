import SwiftUI

/// The Home tab: one row of cards as tall as the tab, inside an 8-pt outer padding, laid out
/// by `HomeCardLayout` from what the features and `HomeWidgetSettings` turn on. Content fades
/// and slides from the top as the island opens.
struct NotchHomeTabView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var layout = HomeLayoutState.shared
    @ObservedObject private var widgets = HomeWidgetSettings.shared
    @ObservedObject private var media = MediaSettings.shared
    /// Mirrors `TimerManager.isActive` alone, so the tab does not redraw on every tick.
    @State private var timerActive = TimerManager.shared.isActive

    var body: some View {
        GeometryReader { proxy in
            let slots = HomeCardLayout.plan(
                kinds,
                width: proxy.size.width,
                height: proxy.size.height,
                timerRunning: timerActive,
                preferredWidths: [.lyrics: CGFloat(media.lyricsPanelWidth)]
            )
            if slots.isEmpty {
                HomeEmptyView()
            } else {
                let showsLyricsCard = slots.contains { $0.kind == .lyrics }
                HStack(spacing: HomeCardLayout.spacing) {
                    ForEach(slots, id: \.kind) { slot in
                        card(slot.kind, height: proxy.size.height, showsLyricsCard: showsLyricsCard)
                            .frame(width: slot.width, height: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.3), value: slots)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(TimerManager.shared.$isActive.removeDuplicates()) { timerActive = $0 }
        .transition(.opacity.animation(.smooth.speed(0.9)).combined(with: .move(edge: .top)))
    }

    private var kinds: Set<HomeCardKind> {
        var kinds = Set<HomeCardKind>()
        if layout.showsMediaPlayer {
            kinds.insert(.media)
            if media.enableLyrics && !layout.showsCalendar { kinds.insert(.lyrics) }
        }
        if layout.showsCalendar { kinds.insert(.calendar) }
        if layout.showsMirror { kinds.insert(.mirror) }
        if widgets.timerCard.isShown(timerActive: timerActive) { kinds.insert(.timer) }
        if widgets.showsApps { kinds.insert(.apps) }
        if widgets.showsWeather { kinds.insert(.weather) }
        return kinds
    }

    @ViewBuilder
    private func card(_ kind: HomeCardKind, height: CGFloat, showsLyricsCard: Bool) -> some View {
        switch kind {
        case .timer:
            HomeTimerCard(openTimerTab: model.availableTabs.contains(.timer) ? { model.selectTab(.timer) } : nil)
        case .media:
            HomeMediaSlot(model: model, showsInlineLyrics: media.enableLyrics && !showsLyricsCard)
        case .lyrics:
            HomeLyricsCard()
        case .apps:
            HomeAppsGrid(height: height)
        case .calendar:
            HomeCalendarCard(model: model)
        case .weather:
            HomeWeatherCard(model: model)
        case .mirror:
            HomeMirrorSlot(model: model)
        }
    }
}

private struct HomeEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Nothing on Home")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Turn on Home cards, the player or the calendar in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
