import CoreLocation
import Foundation

enum WeatherLocationAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

enum WeatherLocationError: Error, Equatable {
    case denied
    case unavailable
}

@MainActor
protocol WeatherLocating: AnyObject {
    var access: WeatherLocationAccess { get }
    /// Called on the main actor whenever `access` may have changed.
    var onAccessChange: (() -> Void)? { get set }
    /// Asks for permission; only called after the user clicks.
    func requestAccess()
    /// The current position to about a kilometre and, when it can be found, the town's name.
    func locate() async throws -> WeatherPlace
}

/// One-shot, kilometre-accuracy positions from Core Location, named by reverse geocoding.
@MainActor
final class WeatherLocator: NSObject, WeatherLocating {
    var onAccessChange: (() -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var waiting: [CheckedContinuation<WeatherCoordinate, any Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var access: WeatherLocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        default: .granted
        }
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func locate() async throws -> WeatherPlace {
        let coordinate = try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
        return WeatherPlace(name: await placeName(for: coordinate), coordinate: coordinate)
    }

    private func placeName(for coordinate: WeatherCoordinate) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                let placemark = placemarks?.first
                continuation.resume(returning: placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.name ?? "")
            }
        }
    }

    private func finish(_ result: Result<WeatherCoordinate, any Error>) {
        let continuations = waiting
        waiting.removeAll()
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }
}

extension WeatherLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onAccessChange?() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let position = WeatherCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        MainActor.assumeIsolated { finish(.success(position)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            finish(.failure(denied ? WeatherLocationError.denied : WeatherLocationError.unavailable))
        }
    }
}
