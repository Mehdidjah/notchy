import Foundation

/// How long a Keep Awake session lasts. The raw values are the stored
/// preference values.
enum CaffeinateDuration: String, CaseIterable, Identifiable, Sendable {
    case indefinite
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours

    var id: String { rawValue }

    /// Session length in seconds, or nil for a session that runs until turned off.
    var seconds: TimeInterval? {
        switch self {
        case .indefinite: nil
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        }
    }

    var displayName: String {
        switch self {
        case .indefinite: "Until turned off"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }

    /// When a session started at `start` ends on its own, or nil when it never does.
    func expiry(from start: Date) -> Date? {
        seconds.map { start.addingTimeInterval($0) }
    }

    /// Countdown text: `M:SS` below an hour and `H:MM:SS` from an hour up. Rounds up, so the
    /// last fraction of a second reads "0:01" rather than "0:00".
    static func remainingLabel(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
