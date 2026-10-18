import Combine
import SwiftUI

/// Which of the Home tab's own cards show. The player, calendar and camera mirror follow
/// their features' settings through `HomeLayoutState`.
@MainActor
final class HomeWidgetSettings: ObservableObject {
    static let shared = HomeWidgetSettings()

    enum TimerCard: String, CaseIterable, Identifiable, Sendable {
        case always
        case whileRunning
        case off

        var id: Self { self }

        var title: String {
            switch self {
            case .always: "Always"
            case .whileRunning: "While a timer runs"
            case .off: "Off"
            }
        }

        func isShown(timerActive: Bool) -> Bool {
            switch self {
            case .always: true
            case .whileRunning: timerActive
            case .off: false
            }
        }
    }

    private enum Key {
        static let timerCard = "home.timerCard"
    }

    @Published var timerCard: TimerCard {
        didSet { defaults.set(timerCard.rawValue, forKey: Key.timerCard) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timerCard = defaults.string(forKey: Key.timerCard).flatMap(TimerCard.init(rawValue:)) ?? .always
    }
}

/// Settings → Home.
struct HomeSettingsSection: View {
    @ObservedObject var widgets: HomeWidgetSettings

    init(widgets: HomeWidgetSettings = .shared) {
        self.widgets = widgets
    }

    var body: some View {
        Section("Cards") {
            Picker("Timer", selection: $widgets.timerCard) {
                ForEach(HomeWidgetSettings.TimerCard.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text("The player, calendar and camera mirror follow their own settings. When the island is too narrow for every card, the extras are left out first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
