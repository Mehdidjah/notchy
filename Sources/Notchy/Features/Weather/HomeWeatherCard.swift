import AppKit
import SwiftUI

/// Home-tab weather card: one sentence giving the temperature, the place, how warm it feels
/// and the sky, such as "27° now in Lisbon feels 28° ☁ Partly Cloudy". Until there is a
/// report it says what is missing, with a button to fix it. A click opens the weather app.
struct HomeWeatherCard: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var store: WeatherStore

    init(model: NotchViewModel, store: WeatherStore = .shared) {
        self.model = model
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        HomeCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12)) {
            if let report = store.currentReport {
                Self.sentence(for: report)
                    .font(.system(size: 24, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: .continuous))
        .onTapGesture {
            if store.currentReport != nil { openWeatherApp() }
        }
        .accessibilityElement(children: .combine)
        .onAppear { store.refreshIfNeeded() }
        .onChange(of: model.state.showsShelfContent) { _, isOpen in
            if isOpen { store.refreshIfNeeded() }
        }
    }

    static func sentence(for report: WeatherReport) -> Text {
        let primary = HomeCardPalette.primaryText
        let secondary = HomeCardPalette.secondaryText
        let temperature = Text(WeatherReport.degrees(report.temperature)).foregroundStyle(primary)
        let feelsLike = Text(WeatherReport.degrees(report.apparentTemperature)).foregroundStyle(primary)
        let symbol = Text(Image(systemName: report.condition.symbol(isDay: report.isDay))).foregroundStyle(primary)
        let sky = Text(report.condition.description).foregroundStyle(primary)
        let feels = Text("feels").foregroundStyle(secondary)
        guard !report.place.isEmpty else {
            return Text("\(temperature) \(Text("now,").foregroundStyle(secondary)) \(feels) \(feelsLike) \(symbol) \(sky)")
        }
        let place = Text(report.place).foregroundStyle(primary)
        return Text("\(temperature) \(Text("now in").foregroundStyle(secondary)) \(place) \(feels) \(feelsLike) \(symbol) \(sky)")
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Weather", systemImage: "cloud.sun")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeCardPalette.secondaryText)
            Spacer(minLength: 0)
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeCardPalette.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                HomeCapsuleButton(title: action.title, isDisabled: store.isLoading, action: action.perform)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var message: String {
        switch store.status {
        case .needsLocationAccess: "See the weather where you are."
        case .locationDenied: "Location access is off. Choose a city in Settings."
        case .needsCity: "Choose a city in Settings."
        case .cityNotFound: "That city wasn't found. Check its name in Settings."
        case .failed: "The weather can't be reached right now."
        case .idle, .loading: "Checking the weather…"
        }
    }

    private var action: (title: String, perform: () -> Void)? {
        switch store.status {
        case .needsLocationAccess: ("Show Weather", { store.requestLocationAccess() })
        case .locationDenied, .needsCity, .cityNotFound: ("Open Settings", { model.requestSettings() })
        case .failed: ("Try Again", { store.refresh() })
        case .idle, .loading: nil
        }
    }

    private func openWeatherApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// Settings rows for the weather card: where to report and in which unit.
struct WeatherSettingsRows: View {
    @ObservedObject var settings: WeatherSettings
    @State private var cityDraft: String

    init(settings: WeatherSettings) {
        self.settings = settings
        _cityDraft = State(initialValue: settings.city)
    }

    var body: some View {
        Picker("Location", selection: $settings.locationMode) {
            ForEach(WeatherSettings.LocationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        if settings.locationMode == .city {
            TextField("City", text: $cityDraft, prompt: Text("Lisbon"))
                .onSubmit { commitCity() }
                .onDisappear { commitCity() }
        }
        Picker("Units", selection: $settings.unit) {
            ForEach(WeatherSettings.Unit.allCases) { unit in
                Text(unit.title).tag(unit)
            }
        }
        Text("Forecasts come from Open-Meteo, which is sent the location rounded to about a kilometre, or the city.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func commitCity() {
        if cityDraft != settings.city { settings.city = cityDraft }
    }
}
