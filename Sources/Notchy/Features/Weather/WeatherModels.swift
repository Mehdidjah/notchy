import Combine
import Foundation

/// A WMO weather interpretation code as words and an outlined symbol.
struct WeatherCondition: Equatable, Sendable {
    let description: String
    let daySymbol: String
    let nightSymbol: String

    func symbol(isDay: Bool) -> String { isDay ? daySymbol : nightSymbol }

    init(description: String, daySymbol: String, nightSymbol: String? = nil) {
        self.description = description
        self.daySymbol = daySymbol
        self.nightSymbol = nightSymbol ?? daySymbol
    }

    init(code: Int) {
        switch code {
        case 0: self.init(description: "Clear", daySymbol: "sun.max", nightSymbol: "moon.stars")
        case 1: self.init(description: "Mostly Clear", daySymbol: "sun.max", nightSymbol: "moon")
        case 2: self.init(description: "Partly Cloudy", daySymbol: "cloud.sun", nightSymbol: "cloud.moon")
        case 3: self.init(description: "Cloudy", daySymbol: "cloud")
        case 45, 48: self.init(description: "Foggy", daySymbol: "cloud.fog")
        case 51, 53, 55: self.init(description: "Drizzle", daySymbol: "cloud.drizzle")
        case 56, 57: self.init(description: "Freezing Drizzle", daySymbol: "cloud.sleet")
        case 61: self.init(description: "Light Rain", daySymbol: "cloud.rain")
        case 63: self.init(description: "Rain", daySymbol: "cloud.rain")
        case 65: self.init(description: "Heavy Rain", daySymbol: "cloud.heavyrain")
        case 66, 67: self.init(description: "Freezing Rain", daySymbol: "cloud.sleet")
        case 71: self.init(description: "Light Snow", daySymbol: "cloud.snow")
        case 73, 77: self.init(description: "Snow", daySymbol: "cloud.snow")
        case 75: self.init(description: "Heavy Snow", daySymbol: "cloud.snow")
        case 80, 81: self.init(description: "Showers", daySymbol: "cloud.sun.rain", nightSymbol: "cloud.moon.rain")
        case 82: self.init(description: "Heavy Showers", daySymbol: "cloud.heavyrain")
        case 85, 86: self.init(description: "Snow Showers", daySymbol: "cloud.snow")
        case 95: self.init(description: "Thunderstorms", daySymbol: "cloud.bolt")
        case 96, 99: self.init(description: "Thunderstorms", daySymbol: "cloud.bolt.rain")
        default: self.init(description: "Weather", daySymbol: "cloud")
        }
    }
}

/// The current weather for one place, as last fetched.
struct WeatherReport: Codable, Equatable, Sendable {
    var temperature: Double
    var apparentTemperature: Double
    var code: Int
    var isDay: Bool
    /// The place's name, or empty when it could not be named.
    var place: String
    /// The settings the report answers, so a changed location or unit refetches.
    var query: WeatherQuery
    var fetchedAt: Date

    var condition: WeatherCondition { WeatherCondition(code: code) }

    static func degrees(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }
}

/// Where and in which unit the weather is asked for.
struct WeatherQuery: Codable, Hashable, Sendable {
    enum Place: Codable, Hashable, Sendable {
        case currentLocation
        case city(String)
    }

    var place: Place
    var fahrenheit: Bool
}

/// Settings → Home → Weather.
@MainActor
final class WeatherSettings: ObservableObject {
    static let shared = WeatherSettings()

    enum LocationMode: String, CaseIterable, Identifiable, Sendable {
        case current
        case city

        var id: Self { self }

        var title: String {
            switch self {
            case .current: "Current Location"
            case .city: "City"
            }
        }
    }

    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case automatic
        case celsius
        case fahrenheit

        var id: Self { self }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .celsius: "Celsius"
            case .fahrenheit: "Fahrenheit"
            }
        }
    }

    private enum Key {
        static let locationMode = "weather.locationMode"
        static let city = "weather.city"
        static let unit = "weather.unit"
    }

    @Published var locationMode: LocationMode {
        didSet { defaults.set(locationMode.rawValue, forKey: Key.locationMode) }
    }
    @Published var city: String {
        didSet { defaults.set(city, forKey: Key.city) }
    }
    @Published var unit: Unit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit) }
    }

    private let defaults: UserDefaults
    private let locale: Locale

    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        self.locale = locale
        locationMode = defaults.string(forKey: Key.locationMode).flatMap(LocationMode.init(rawValue:)) ?? .current
        city = defaults.string(forKey: Key.city) ?? ""
        unit = defaults.string(forKey: Key.unit).flatMap(Unit.init(rawValue:)) ?? .automatic
    }

    /// What to fetch now. Automatic units follow the locale's measurement system.
    var query: WeatherQuery {
        let fahrenheit = switch unit {
        case .automatic: locale.measurementSystem == .us
        case .celsius: false
        case .fahrenheit: true
        }
        let place: WeatherQuery.Place = switch locationMode {
        case .current: .currentLocation
        case .city: .city(city.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return WeatherQuery(place: place, fahrenheit: fahrenheit)
    }
}
