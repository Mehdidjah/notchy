import Combine
import Foundation

/// The weather the Home card shows. It fetches only when asked while there is no report for
/// the current settings or the report is over 20 minutes old, and waits 2 minutes after a
/// failure before trying again. The last report is kept across launches.
@MainActor
final class WeatherStore: ObservableObject {
    enum Status: Equatable, Sendable {
        case idle
        case loading
        case needsLocationAccess
        case locationDenied
        case needsCity
        case cityNotFound
        case failed
    }

    static let shared = WeatherStore()
    static let refreshInterval: TimeInterval = 20 * 60
    static let retryInterval: TimeInterval = 2 * 60
    private static let reportKey = "weather.lastReport"

    @Published private(set) var report: WeatherReport?
    @Published private(set) var status: Status = .idle

    let settings: WeatherSettings
    private let fetcher: any WeatherFetching
    private let locator: any WeatherLocating
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var loadTask: Task<Void, Never>?
    private var generation = 0
    private var lastFailure: Date?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: WeatherSettings = .shared,
        fetcher: any WeatherFetching = OpenMeteoClient(),
        locator: (any WeatherLocating)? = nil,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.fetcher = fetcher
        self.locator = locator ?? WeatherLocator()
        self.defaults = defaults
        self.clock = clock
        report = defaults.data(forKey: Self.reportKey).flatMap { try? JSONDecoder().decode(WeatherReport.self, from: $0) }
        self.locator.onAccessChange = { [weak self] in self?.accessChanged() }
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
    }

    /// The report, when it answers the current settings.
    var currentReport: WeatherReport? {
        guard let report, report.query == settings.query else { return nil }
        return report
    }

    var isLoading: Bool { loadTask != nil }

    func refreshIfNeeded() {
        guard loadTask == nil else { return }
        let now = clock()
        if let report = currentReport, now.timeIntervalSince(report.fetchedAt) < Self.refreshInterval { return }
        if let lastFailure, now.timeIntervalSince(lastFailure) < Self.retryInterval { return }
        refresh()
    }

    func refresh() {
        loadTask?.cancel()
        loadTask = nil
        generation &+= 1
        let query = settings.query
        switch query.place {
        case .currentLocation:
            switch locator.access {
            case .notDetermined:
                status = .needsLocationAccess
                return
            case .denied:
                status = .locationDenied
                return
            case .granted:
                break
            }
        case .city(let city):
            if city.isEmpty {
                status = .needsCity
                return
            }
        }
        status = .loading
        let generation = generation
        loadTask = Task { [weak self] in
            await self?.load(query, generation: generation)
        }
    }

    func requestLocationAccess() {
        locator.requestAccess()
    }

    private func load(_ query: WeatherQuery, generation: Int) async {
        var outcome = Status.idle
        do {
            let place: WeatherPlace
            switch query.place {
            case .currentLocation:
                place = try await locator.locate()
            case .city(let city):
                guard let found = try await fetcher.place(named: city) else { throw WeatherLookupError.cityNotFound }
                place = found
            }
            let conditions = try await fetcher.conditions(at: place.coordinate, fahrenheit: query.fahrenheit)
            guard generation == self.generation else { return }
            let report = WeatherReport(
                temperature: conditions.temperature,
                apparentTemperature: conditions.apparentTemperature,
                code: conditions.code,
                isDay: conditions.isDay,
                place: place.name,
                query: query,
                fetchedAt: clock()
            )
            self.report = report
            defaults.set(try? JSONEncoder().encode(report), forKey: Self.reportKey)
        } catch WeatherLocationError.denied {
            outcome = .locationDenied
        } catch WeatherLookupError.cityNotFound {
            outcome = .cityNotFound
        } catch {
            outcome = .failed
        }
        guard generation == self.generation else { return }
        lastFailure = outcome == .idle ? nil : clock()
        status = outcome
        loadTask = nil
    }

    private func accessChanged() {
        guard settings.query.place == .currentLocation else { return }
        switch locator.access {
        case .granted:
            lastFailure = nil
            if status == .needsLocationAccess || status == .locationDenied { refresh() } else { refreshIfNeeded() }
        case .denied:
            loadTask?.cancel()
            loadTask = nil
            generation &+= 1
            status = .locationDenied
        case .notDetermined:
            status = .needsLocationAccess
        }
    }

    private func settingsChanged() {
        lastFailure = nil
        if currentReport == nil { refresh() }
    }
}

private enum WeatherLookupError: Error {
    case cityNotFound
}
