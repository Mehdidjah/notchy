import Foundation

struct WeatherCoordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// A named place found for a city search.
struct WeatherPlace: Equatable, Sendable {
    var name: String
    var coordinate: WeatherCoordinate
}

/// Current conditions as the forecast service reports them.
struct WeatherConditions: Equatable, Sendable {
    var temperature: Double
    var apparentTemperature: Double
    var code: Int
    var isDay: Bool
}

protocol WeatherFetching: Sendable {
    func conditions(at coordinate: WeatherCoordinate, fahrenheit: Bool) async throws -> WeatherConditions
    func place(named city: String) async throws -> WeatherPlace?
}

enum WeatherFetchError: Error, Equatable {
    case badResponse
}

/// Open-Meteo's free forecast and geocoding endpoints, which need no account. Coordinates are
/// sent rounded to two decimals, about a kilometre.
struct OpenMeteoClient: WeatherFetching {
    var session: URLSession = URLSession(configuration: .ephemeral)

    static func forecastURL(for coordinate: WeatherCoordinate, fahrenheit: Bool) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components?.url
    }

    static func geocodingURL(for city: String, language: String) -> URL? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json")
        ]
        return components?.url
    }

    static func parseConditions(_ data: Data) throws -> WeatherConditions {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature: Double
                let apparentTemperature: Double
                let weatherCode: Int
                let isDay: Int

                enum CodingKeys: String, CodingKey {
                    case temperature = "temperature_2m"
                    case apparentTemperature = "apparent_temperature"
                    case weatherCode = "weather_code"
                    case isDay = "is_day"
                }
            }

            let current: Current
        }
        let current = try JSONDecoder().decode(Response.self, from: data).current
        return WeatherConditions(
            temperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            code: current.weatherCode,
            isDay: current.isDay != 0
        )
    }

    static func parsePlace(_ data: Data) throws -> WeatherPlace? {
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
            }

            let results: [Result]?
        }
        guard let first = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return WeatherPlace(name: first.name, coordinate: WeatherCoordinate(latitude: first.latitude, longitude: first.longitude))
    }

    func conditions(at coordinate: WeatherCoordinate, fahrenheit: Bool) async throws -> WeatherConditions {
        guard let url = Self.forecastURL(for: coordinate, fahrenheit: fahrenheit) else { throw WeatherFetchError.badResponse }
        return try Self.parseConditions(try await data(from: url))
    }

    func place(named city: String) async throws -> WeatherPlace? {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard let url = Self.geocodingURL(for: city, language: language) else { throw WeatherFetchError.badResponse }
        return try Self.parsePlace(try await data(from: url))
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Notchy", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherFetchError.badResponse }
        return data
    }
}
