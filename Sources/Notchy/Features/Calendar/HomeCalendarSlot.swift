import SwiftUI

/// Home-tab calendar slot: the compact 120-pt panel beside a media player, or the
/// standalone month view when no player is shown. The date header / month grid is
/// always drawn; until EventKit access is granted the event area asks for it instead of
/// showing the day's events. Opening the island always lands on today.
struct HomeCalendarSlot: View {
    @ObservedObject var model: NotchViewModel
    let compact: Bool
    @ObservedObject private var store: CalendarStore
    @ObservedObject private var settings: CalendarSettings
    @ObservedObject private var homeLayout: HomeLayoutState
    /// Bumped each time the island opens, so the standalone grid re-centres on today.
    @State private var openGeneration = 0

    init(model: NotchViewModel, compact: Bool) {
        self.model = model
        self.compact = compact
        _store = ObservedObject(wrappedValue: CalendarStore.shared)
        _settings = ObservedObject(wrappedValue: CalendarSettings.shared)
        _homeLayout = ObservedObject(wrappedValue: HomeLayoutState.shared)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { store.isHoveringCalendar = $0 }
            .onAppear {
                store.refreshAuthorizationStatus()
                store.resetToToday()
            }
            .onDisappear { store.isHoveringCalendar = false }
            .onChange(of: model.state.showsShelfContent) { _, isOpen in
                // The compact view resets on every open/close, the standalone view
                // also re-centres its grid when the notch opens.
                store.resetToToday()
                if isOpen {
                    store.refreshAuthorizationStatus()
                    openGeneration &+= 1
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            CalendarCompactPanel(store: store, settings: settings, hapticsEnabled: model.settings.hapticsEnabled)
        } else {
            CalendarStandalonePanel(
                store: store,
                settings: settings,
                height: standaloneHeight,
                openGeneration: openGeneration
            )
        }
    }

    /// The open notch height less the header and 36 pt, never under 130.
    private var standaloneHeight: CGFloat {
        CalendarLayout.standaloneHeight(
            openHeight: NotchTab.home.openHeight + homeLayout.extraHeight,
            closedHeight: model.notchGeometry.topInset
        )
    }
}
