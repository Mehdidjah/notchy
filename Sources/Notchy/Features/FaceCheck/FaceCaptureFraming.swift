import CoreGraphics

/// Vision may estimate a face box beyond the image when the chin or forehead is cut off.
/// That is a positioning issue, not a failed model. Never manufacture the missing pixels
/// or clip the box into an apparently valid sample for identity or passive screening.
enum FaceCaptureFraming {
    static let guidance = "Move back until your whole face fits in the circle."

    static func contains(_ bounds: CGRect) -> Bool {
        bounds.minX.isFinite && bounds.minY.isFinite &&
        bounds.width.isFinite && bounds.height.isFinite &&
        bounds.width > 0 && bounds.height > 0 &&
        bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 1 && bounds.maxY <= 1
    }
}
