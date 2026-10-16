import Combine
import Foundation

/// How the download activity draws its right wing.
enum DownloadIndicatorStyle: String, CaseIterable, Identifiable, Sendable {
    /// A 40-pt linear bar: indeterminate, or filling when the browser publishes progress.
    case progress
    /// A 16-pt ring with a spinning quarter arc, or a filling arc when progress is known.
    case circle

    var id: Self { self }

    var label: String {
        switch self {
        case .progress: "Progress"
        case .circle: "Circle"
        }
    }
}

/// Download activity preferences, stored under `downloads.*` keys. Defaults follow Atoll:
/// detection on, linear progress style, speed hidden.
@MainActor
final class DownloadsSettings: ObservableObject {
    enum Key {
        static let enableDownloadDetection = "downloads.enableDownloadDetection"
        static let showDownloadSpeed = "downloads.showDownloadSpeed"
        static let indicatorStyle = "downloads.indicatorStyle"
    }

    static let shared = DownloadsSettings()

    private let defaults: UserDefaults

    /// Watch ~/Downloads for browsers' partial files and show the live activity.
    @Published var enableDownloadDetection: Bool {
        didSet { defaults.set(enableDownloadDetection, forKey: Key.enableDownloadDetection) }
    }

    /// Show the current rate ("1.2 MB/s") beside the indicator.
    @Published var showDownloadSpeed: Bool {
        didSet { defaults.set(showDownloadSpeed, forKey: Key.showDownloadSpeed) }
    }

    @Published var indicatorStyle: DownloadIndicatorStyle {
        didSet { defaults.set(indicatorStyle.rawValue, forKey: Key.indicatorStyle) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enableDownloadDetection = defaults.object(forKey: Key.enableDownloadDetection) as? Bool ?? true
        showDownloadSpeed = defaults.object(forKey: Key.showDownloadSpeed) as? Bool ?? false
        indicatorStyle = DownloadIndicatorStyle(rawValue: defaults.string(forKey: Key.indicatorStyle) ?? "") ?? .progress
    }
}
