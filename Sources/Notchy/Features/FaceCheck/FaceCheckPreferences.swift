import Combine
import Foundation

enum FaceUnlockAnimationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal, original
    var id: Self { self }
    var title: String { self == .minimal ? "Minimal" : "Original" }
}

enum FaceLivenessStrength: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, heavy
    var id: Self { self }
    var title: String { self == .light ? "Light" : "Heavy" }
}

enum FaceSessionLifetime: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7, fourteenDays = 14, thirtyDays = 30, never = 0
    var id: Self { self }
    var title: String { self == .never ? "Never" : "\(rawValue) days" }
    var interval: TimeInterval? { self == .never ? nil : Double(rawValue) * 86_400 }
}

/// A snapshot is frozen for each attempt. Changing preferences cancels any pending scan;
/// a result produced under an earlier policy can never release the password.
struct FaceCheckOptions: Codable, Equatable, Sendable {
    var onWake = true
    var onLock = true
    var onSpace = false
    var displayID = "main"
    var retryOnHover = true
    var autoRetry = false
    var haptics = true
    var detectionDuration: Double = 10
    var showAnimation = true
    var animationStyle: FaceUnlockAnimationStyle = .minimal
    var sessionLifetime: FaceSessionLifetime = .thirtyDays
    var defaultCameraID = ""
    var builtInCameraID = ""
    var externalCameraID = ""
    /// Discrete slider positions: less strict, default, more strict.
    var matchConfidence: Double = 1
    /// Discrete slider positions: close, default, far.
    var detectionDistance: Double = 1
    var livenessEnabled = true
    var livenessStrength: FaceLivenessStrength = .light

    var scanDuration: TimeInterval { Self.clamp(detectionDuration, to: 3...30, fallback: 10) }
    var minimumFaceWidth: Double {
        [0.22, 0.14, 0.08][Int(Self.clamp(detectionDistance, to: 0...2, fallback: 1).rounded())]
    }

    func maximumDistance(profile: FaceRecognitionProfile, validated: Bool = false) -> Float {
        let index = Int(Self.clamp(matchConfidence, to: 0...2, fallback: 1).rounded())
        if profile.metric == .euclidean { return [0.60, 0.55, 0.50][index] }
        let distance = max(0.01, profile.strictDistance + Float(1 - index) * 0.05)
        // A released calibration is an upper bound, never weakened by a preference.
        return validated ? min(profile.strictDistance, distance) : distance
    }

    func cameraID(forBuiltInDisplay builtIn: Bool) -> String {
        let override = builtIn ? builtInCameraID : externalCameraID
        return override.isEmpty ? defaultCameraID : override
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

@MainActor
final class FaceCheckPreferences: ObservableObject {
    static let shared = FaceCheckPreferences()
    static let key = "faceCheck.options.v1"
    private let defaults: UserDefaults
    @Published var options: FaceCheckOptions {
        didSet {
            if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(FaceCheckOptions.self, from: data) {
            options = saved
        } else {
            var initial = FaceCheckOptions()
            switch defaults.string(forKey: "faceCheck.matchPreset") {
            case "strict": initial.matchConfidence = 2
            case "relaxed": initial.matchConfidence = 0
            default: break
            }
            options = initial
        }
    }
}
