import Combine
import Foundation

/// Outline of the camera mirror. Atoll: "Rectangular" (default) or "Circular".
enum MirrorShape: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case circle

    var id: String { rawValue }

    /// Label in Settings; Atoll calls the rectangle "Square".
    var displayName: String {
        switch self {
        case .rectangle: "Square"
        case .circle: "Circle"
        }
    }

    /// Corner radius of the live preview. Atoll uses the opened album-art radius (13) for the
    /// square, and a radius larger than half the side for the circle.
    var previewCornerRadius: CGFloat {
        switch self {
        case .rectangle: 13
        case .circle: 100
        }
    }

    /// Corner radius of the "Mirror" placeholder tile; Atoll draws it 1 pt tighter (12).
    var placeholderCornerRadius: CGFloat {
        switch self {
        case .rectangle: 12
        case .circle: 100
        }
    }
}

/// Camera mirror preferences, stored under `mirror.*` in UserDefaults with Atoll's defaults:
/// off, square, and the automatic camera choice.
@MainActor
final class MirrorSettings: ObservableObject {
    enum Key {
        static let isEnabled = "mirror.enabled"
        static let shape = "mirror.shape"
        static let cameraID = "mirror.cameraID"
    }

    static let shared = MirrorSettings()

    private let defaults: UserDefaults

    /// Atoll's `showMirror`: shows the mirror in Home and the camera button in the header.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    @Published var shape: MirrorShape {
        didSet { defaults.set(shape.rawValue, forKey: Key.shape) }
    }
    /// `AVCaptureDevice.uniqueID` of the chosen camera; empty picks the front camera.
    @Published var cameraID: String {
        didSet { defaults.set(cameraID, forKey: Key.cameraID) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? false
        shape = MirrorShape(rawValue: defaults.string(forKey: Key.shape) ?? "") ?? .rectangle
        cameraID = defaults.string(forKey: Key.cameraID) ?? ""
    }
}
