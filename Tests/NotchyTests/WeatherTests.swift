import Foundation
import Testing
@testable import Notchy

struct WeatherFormattingTests {
    @Test func weatherCodesMapToWordsAndOutlinedSymbols() {
        #expect(WeatherCondition(code: 0).symbol(isDay: true) == "sun.max")
        #expect(WeatherCondition(code: 0).symbol(isDay: false) == "moon.stars")
        #expect(WeatherCondition(code: 2) == WeatherCondition(description: "Partly Cloudy", daySymbol: "cloud.sun", nightSymbol: "cloud.moon"))
        #expect(WeatherCondition(code: 3).symbol(isDay: false) == "cloud")
        #expect(WeatherCondition(code: 63).description == "Rain")
        #expect(WeatherCondition(code: 99).symbol(isDay: true) == "cloud.bolt.rain")
        #expect(WeatherCondition(code: 1234).description == "Weather")
    }

    @Test func temperaturesRoundToWholeDegreesWithoutNegativeZero() {
        #expect(WeatherReport.degrees(26.6) == "27°")
        #expect(WeatherReport.degrees(-0.4) == "0°")
        #expect(WeatherReport.degrees(-3.5) == "-4°")
    }

    @Test func forecastRequestsRoundTheCoordinates() throws {
        let url = try #require(OpenMeteoClient.forecastURL(
            for: WeatherCoordinate(latitude: 38.722_252, longitude: -9.139_337), fahrenheit: true))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.open-meteo.com")
        #expect(query["latitude"] == "38.72")
        #expect(query["longitude"] == "-9.14")
        #expect(query["temperature_unit"] == "fahrenheit")
        #expect(query["current"] == "temperature_2m,apparent_temperature,weather_code,is_day")
    }

    @Test func forecastAndPlaceAnswersParse() throws {
        let forecast = Data("""
        {"latitude":38.72,"current":{"time":"2026-07-04T21:00","temperature_2m":26.8,"apparent_temperature":28.1,"weather_code":2,"is_day":0}}
        """.utf8)
        #expect(try OpenMeteoClient.parseConditions(forecast)
            == WeatherConditions(temperature: 26.8, apparentTemperature: 28.1, code: 2, isDay: false))

        let place = Data(#"{"results":[{"name":"Lisbon","latitude":38.71667,"longitude":-9.13333,"country":"Portugal"}]}"#.utf8)
        #expect(try OpenMeteoClient.parsePlace(place)
            == WeatherPlace(name: "Lisbon", coordinate: WeatherCoordinate(latitude: 38.71667, longitude: -9.13333)))
        #expect(try OpenMeteoClient.parsePlace(Data(#"{"generationtime_ms":0.2}"#.utf8)) == nil)
        #expect(throws: (any Error).self) { try OpenMeteoClient.parseConditions(Data("{}".utf8)) }
    }

    @MainActor
    @Test func automaticUnitsFollowTheLocaleAndCitiesAreTrimmed() {
        let suite = "notchy.weather-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(WeatherSettings(defaults: defaults, locale: Locale(identifier: "en_US")).query.fahrenheit)
        let settings = WeatherSettings(defaults: defaults, locale: Locale(identifier: "en_GB"))
        #expect(settings.query == WeatherQuery(place: .currentLocation, fahrenheit: false))

        settings.locationMode = .city
        settings.city = "  Lisbon "
        settings.unit = .fahrenheit
        #expect(settings.query == WeatherQuery(place: .city("Lisbon"), fahrenheit: true))
        let reloaded = WeatherSettings(defaults: defaults, locale: Locale(identifier: "en_GB"))
        #expect(reloaded.query == settings.query)
    }
}

@MainActor
struct WeatherStoreTests {
    private static let lisbon = WeatherCoordinate(latitude: 38.72, longitude: -9.14)

    @MainActor
    private final class Fixture {
        let suite = "notchy.weather-store.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: WeatherSettings
        let fetcher = StubWeatherFetcher()
        let locator = StubWeatherLocator()
        var now = Date(timeIntervalSince1970: 1_800_000_000)

        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = WeatherSettings(defaults: defaults, locale: Locale(identifier: "en_GB"))
        }

        func makeStore() -> WeatherStore {
            WeatherStore(settings: settings, fetcher: fetcher, locator: locator, defaults: defaults) { [unowned self] in now }
        }

        deinit { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    private func settle(_ store: WeatherStore) async {
        for _ in 0..<200 where store.isLoading {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Lets the store see a settings change, which reaches it on the next main-queue turn.
    private func settleAfterSettingsChange(_ store: WeatherStore) async {
        try? await Task.sleep(for: .milliseconds(20))
        await settle(store)
    }

    @Test func theCurrentLocationWaitsForPermissionAndThenFetches() async {
        let fixture = Fixture()
        fixture.locator.place = WeatherPlace(name: "Lisbon", coordinate: Self.lisbon)
        let store = fixture.makeStore()

        store.refreshIfNeeded()
        #expect(store.status == .needsLocationAccess)
        #expect(await fixture.fetcher.conditionRequests.isEmpty)

        store.requestLocationAccess()
        #expect(fixture.locator.accessRequests == 1)
        fixture.locator.grant()
        await settle(store)

        #expect(store.status == .idle)
        #expect(store.currentReport?.place == "Lisbon")
        #expect(store.currentReport?.temperature == 26.8)
        #expect(await fixture.fetcher.conditionRequests == [Self.lisbon])
        // The report survives a relaunch.
        #expect(fixture.makeStore().currentReport == store.currentReport)
    }

    @Test func reportsAreReusedForTwentyMinutes() async {
        let fixture = Fixture()
        fixture.locator.access = .granted
        let store = fixture.makeStore()

        store.refreshIfNeeded()
        await settle(store)
        fixture.now += 19 * 60
        store.refreshIfNeeded()
        await settle(store)
        #expect(await fixture.fetcher.conditionRequests.count == 1)

        fixture.now += 2 * 60
        store.refreshIfNeeded()
        await settle(store)
        #expect(await fixture.fetcher.conditionRequests.count == 2)
    }

    @Test func aFailureWaitsTwoMinutesBeforeTryingAgain() async {
        let fixture = Fixture()
        fixture.locator.access = .granted
        await fixture.fetcher.setFailing(true)
        let store = fixture.makeStore()

        store.refreshIfNeeded()
        await settle(store)
        #expect(store.status == .failed)
        #expect(store.currentReport == nil)

        await fixture.fetcher.setFailing(false)
        fixture.now += 60
        store.refreshIfNeeded()
        await settle(store)
        #expect(store.status == .failed)

        fixture.now += 61
        store.refreshIfNeeded()
        await settle(store)
        #expect(store.status == .idle)
        #expect(store.currentReport != nil)
    }

    @Test func deniedLocationAsksForACity() async {
        let fixture = Fixture()
        fixture.locator.access = .granted
        fixture.locator.error = WeatherLocationError.denied
        let store = fixture.makeStore()

        store.refreshIfNeeded()
        await settle(store)
        #expect(store.status == .locationDenied)

        fixture.locator.access = .denied
        store.refresh()
        #expect(store.status == .locationDenied)
    }

    @Test func citiesAreLookedUpByName() async {
        let fixture = Fixture()
        fixture.settings.locationMode = .city
        let store = fixture.makeStore()

        store.refresh()
        #expect(store.status == .needsCity)

        fixture.settings.city = "Atlantis"
        await settleAfterSettingsChange(store)
        #expect(store.status == .cityNotFound)

        fixture.settings.city = "Lisbon"
        await settleAfterSettingsChange(store)
        #expect(store.status == .idle)
        #expect(store.currentReport?.place == "Lisbon")
        #expect(await fixture.fetcher.placeRequests.suffix(1) == ["Lisbon"])
        #expect(fixture.locator.locateRequests == 0)
    }

    @Test func changingTheUnitFetchesAgain() async {
        let fixture = Fixture()
        fixture.locator.access = .granted
        let store = fixture.makeStore()
        store.refreshIfNeeded()
        await settle(store)
        #expect(store.currentReport?.query.fahrenheit == false)

        fixture.settings.unit = .fahrenheit
        #expect(store.currentReport == nil)
        await settleAfterSettingsChange(store)
        #expect(store.currentReport?.query.fahrenheit == true)
        #expect(await fixture.fetcher.conditionRequests.count == 2)
    }
}

private actor StubWeatherFetcher: WeatherFetching {
    private(set) var conditionRequests: [WeatherCoordinate] = []
    private(set) var placeRequests: [String] = []
    private var failing = false

    func setFailing(_ failing: Bool) { self.failing = failing }

    func conditions(at coordinate: WeatherCoordinate, fahrenheit: Bool) async throws -> WeatherConditions {
        conditionRequests.append(coordinate)
        if failing { throw WeatherFetchError.badResponse }
        return WeatherConditions(temperature: 26.8, apparentTemperature: 28.1, code: 2, isDay: false)
    }

    func place(named city: String) async throws -> WeatherPlace? {
        placeRequests.append(city)
        guard city == "Lisbon" else { return nil }
        return WeatherPlace(name: "Lisbon", coordinate: WeatherCoordinate(latitude: 38.72, longitude: -9.14))
    }
}

@MainActor
private final class StubWeatherLocator: WeatherLocating {
    var access = WeatherLocationAccess.notDetermined
    var onAccessChange: (() -> Void)?
    var place = WeatherPlace(name: "", coordinate: WeatherCoordinate(latitude: 1, longitude: 2))
    var error: (any Error)?
    private(set) var accessRequests = 0
    private(set) var locateRequests = 0

    func requestAccess() { accessRequests += 1 }

    func grant() {
        access = .granted
        onAccessChange?()
    }

    func locate() async throws -> WeatherPlace {
        locateRequests += 1
        if let error { throw error }
        return place
    }
}
