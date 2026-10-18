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
        static let showsApps = "home.showsApps"
        static let showsWeather = "home.showsWeather"
    }

    @Published var timerCard: TimerCard {
        didSet { defaults.set(timerCard.rawValue, forKey: Key.timerCard) }
    }
    @Published var showsApps: Bool {
        didSet { defaults.set(showsApps, forKey: Key.showsApps) }
    }
    @Published var showsWeather: Bool {
        didSet { defaults.set(showsWeather, forKey: Key.showsWeather) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timerCard = defaults.string(forKey: Key.timerCard).flatMap(TimerCard.init(rawValue:)) ?? .always
        showsApps = defaults.object(forKey: Key.showsApps) as? Bool ?? true
        showsWeather = defaults.object(forKey: Key.showsWeather) as? Bool ?? true
    }
}

/// Settings → Home.
struct HomeSettingsSection: View {
    @ObservedObject var widgets: HomeWidgetSettings
    @ObservedObject var apps: HomeAppShortcutsStore
    let weather: WeatherSettings

    init(widgets: HomeWidgetSettings = .shared, apps: HomeAppShortcutsStore = .shared, weather: WeatherSettings = .shared) {
        self.widgets = widgets
        self.apps = apps
        self.weather = weather
    }

    var body: some View {
        Section("Cards") {
            Picker("Timer", selection: $widgets.timerCard) {
                ForEach(HomeWidgetSettings.TimerCard.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("App shortcuts", isOn: $widgets.showsApps)
            Toggle("Weather", isOn: $widgets.showsWeather)
            Text("The player, calendar and camera mirror follow their own settings. When the island is too narrow for every card, the app shortcuts are left out first, then an idle timer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if widgets.showsApps {
            Section("App shortcuts") {
                HomeAppShortcutsSettingsRows(store: apps)
            }
        }
        if widgets.showsWeather {
            Section("Weather") {
                WeatherSettingsRows(settings: weather)
            }
        }
    }
}
