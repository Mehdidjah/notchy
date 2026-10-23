import SwiftUI

/// Geometry and camera-to-screen mapping for the dedicated enrollment surface.
/// Stored pose names remain in camera coordinates; instructions use the person's directions.
enum FaceEnrollmentPresentation {
    static let bodyWidth: CGFloat = 320
    static let height: CGFloat = 344
    static let flare: CGFloat = 16
    static let bottomRadius: CGFloat = 51.5
    static let cameraDiameter: CGFloat = 185
    static let ringDiameter: CGFloat = 240
    static let tickCount = 80
    static let tickWidth = 2.0
    static let accent = Color(red: 52 / 255, green: 153 / 255, blue: 1)
    static let completionHold: Duration = .seconds(3)
    static let closeDuration: Duration = .milliseconds(450)

    /// Clockwise from the top of the mirrored preview, ten ticks per direction.
    static let sectors: [FaceEnrollmentPose] = [
        .up, .upLeft, .left, .downLeft, .down, .downRight, .right, .upRight
    ]

    static func pose(atTick tick: Int) -> FaceEnrollmentPose {
        sectors[((tick + 5) / 10) % sectors.count]
    }

    static func angle(for pose: FaceEnrollmentPose) -> Double? {
        sectors.firstIndex(of: pose).map { Double($0) * 45 }
    }

    static func nextPose(counts: [FaceEnrollmentPose: Int], samplesPerPose: Int) -> FaceEnrollmentPose? {
        FaceEnrollmentPose.guidedOrder.first { (counts[$0] ?? 0) < samplesPerPose }
    }

    static func instruction(for pose: FaceEnrollmentPose) -> String {
        switch pose {
        case .centre: "Look straight at the camera"
        case .right: "Turn your head slightly left"
        case .upRight: "Turn your head to the top left"
        case .up: "Turn your head slightly up"
        case .upLeft: "Turn your head to the top right"
        case .left: "Turn your head slightly right"
        case .downLeft: "Turn your head to the bottom right"
        case .down: "Turn your head slightly down"
        case .downRight: "Turn your head to the bottom left"
        }
    }

    struct Heading: Equatable {
        var degrees = 0.0
        var strength = 0.0

        init(yaw: Double? = nil, pitch: Double? = nil) {
            guard let yaw, let pitch, yaw.isFinite, pitch.isFinite else { return }
            let x = -yaw / 20, y = -pitch / 16
            let distance = hypot(x, y)
            guard distance > 0.15 else { return }
            degrees = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            strength = min(1, distance)
        }

        func emphasis(atTick tick: Int) -> Double {
            let delta = abs(Double(tick) * 4.5 - degrees)
            return max(0, 1 - min(delta, 360 - delta) / 13.5) * strength
        }
    }
}

enum FaceEnrollmentScanPhase: Equatable {
    case scanning, saving, saved, failed(String)

    var isSaved: Bool { self == .saved }
    var failure: String? {
        if case .failed(let message) = self { message } else { nil }
    }
}
