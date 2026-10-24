import CoreGraphics
import Foundation

// MARK: - Landmarks

/// Vision landmarks in image coordinates, with the origin at the top left.
struct FaceLandmarkPoints: Equatable, Sendable {
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    /// Outline of the nose: the wings and the base.
    var nose: [CGPoint]
    /// The crest of the nose, from the bridge down to the tip. Only used when `nose` is empty.
    var noseCrest: [CGPoint]
    var outerLips: [CGPoint]

    init(
        leftEye: [CGPoint] = [],
        rightEye: [CGPoint] = [],
        nose: [CGPoint] = [],
        noseCrest: [CGPoint] = [],
        outerLips: [CGPoint] = []
    ) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.nose = nose
        self.noseCrest = noseCrest
        self.outerLips = outerLips
    }

    /// Converts points measured up from the image's bottom edge (how Vision reports them) into
    /// Face Check's convention, measured down from the top edge.
    func flippedVertically(imageHeight: CGFloat) -> FaceLandmarkPoints {
        func flip(_ points: [CGPoint]) -> [CGPoint] {
            points.map { CGPoint(x: $0.x, y: imageHeight - $0.y) }
        }
        return FaceLandmarkPoints(
            leftEye: flip(leftEye),
            rightEye: flip(rightEye),
            nose: flip(nose),
            noseCrest: flip(noseCrest),
            outerLips: flip(outerLips)
        )
    }
}

// MARK: - Similarity transform

/// A transform of the plane made only of a uniform scale, a rotation and a translation: no
/// shear and never a mirror image, which is exactly the freedom a face has in front of a camera.
///
/// Stored as the complex factor `a + ib` (scale·cos θ, scale·sin θ) plus a translation, so a point
/// maps to `(a·x − b·y + tx, b·x + a·y + ty)`. Composition and inversion stay closed-form.
struct FaceSimilarityTransform: Equatable, Sendable {
    var a: Double
    var b: Double
    var tx: Double
    var ty: Double

    static let identity = FaceSimilarityTransform(a: 1, b: 0, tx: 0, ty: 0)

    init(a: Double, b: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.tx = tx
        self.ty = ty
    }

    /// Rotation in radians, counter-clockwise in a y-up plane (clockwise on screen, where y grows
    /// downward).
    init(scale: Double, rotation: Double, translation: CGPoint) {
        self.init(
            a: scale * cos(rotation),
            b: scale * sin(rotation),
            tx: Double(translation.x),
            ty: Double(translation.y)
        )
    }

    static func translation(x: Double, y: Double) -> FaceSimilarityTransform {
        FaceSimilarityTransform(a: 1, b: 0, tx: x, ty: y)
    }

    static func scaling(_ factor: Double) -> FaceSimilarityTransform {
        FaceSimilarityTransform(a: factor, b: 0, tx: 0, ty: 0)
    }

    var scale: Double { hypot(a, b) }
    var rotation: Double { atan2(b, a) }

    func apply(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        return CGPoint(x: a * x - b * y + tx, y: b * x + a * y + ty)
    }

    /// The transform that undoes this one, or `nil` when this one collapses the plane to a point.
    var inverse: FaceSimilarityTransform? {
        let squaredScale = a * a + b * b
        guard squaredScale > 0, squaredScale.isFinite else { return nil }
        let inverseA = a / squaredScale
        let inverseB = -b / squaredScale
        return FaceSimilarityTransform(
            a: inverseA,
            b: inverseB,
            tx: -(inverseA * tx - inverseB * ty),
            ty: -(inverseB * tx + inverseA * ty)
        )
    }

    /// This transform first, then `next`.
    func followed(by next: FaceSimilarityTransform) -> FaceSimilarityTransform {
        FaceSimilarityTransform(
            a: next.a * a - next.b * b,
            b: next.a * b + next.b * a,
            tx: next.a * tx - next.b * ty + next.tx,
            ty: next.b * tx + next.a * ty + next.ty
        )
    }

    var affineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    /// The similarity that best maps `source` onto `target` in the least-squares sense.
    ///
    /// This is Umeyama's estimate restricted to proper rotations, which in two dimensions has a
    /// closed form: centre both point sets, treat points as complex numbers, and the factor is
    /// `Σ conj(source)·target / Σ |source|²`. Returns `nil` when the sets differ in size, hold fewer than two points,
    /// contain a non-finite coordinate, or either set has collapsed to a single point.
    static func fit(from source: [CGPoint], to target: [CGPoint]) -> FaceSimilarityTransform? {
        guard source.count == target.count, source.count >= 2 else { return nil }
        guard (source + target).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        let count = Double(source.count)
        let sourceMeanX = source.reduce(0) { $0 + Double($1.x) } / count
        let sourceMeanY = source.reduce(0) { $0 + Double($1.y) } / count
        let targetMeanX = target.reduce(0) { $0 + Double($1.x) } / count
        let targetMeanY = target.reduce(0) { $0 + Double($1.y) } / count

        var sourceSpread = 0.0
        var targetSpread = 0.0
        var real = 0.0
        var imaginary = 0.0
        for (s, t) in zip(source, target) {
            let sx = Double(s.x) - sourceMeanX
            let sy = Double(s.y) - sourceMeanY
            let px = Double(t.x) - targetMeanX
            let py = Double(t.y) - targetMeanY
            sourceSpread += sx * sx + sy * sy
            targetSpread += px * px + py * py
            real += sx * px + sy * py
            imaginary += sx * py - sy * px
        }
        // A set that has collapsed to one point says nothing about rotation or scale.
        guard sourceSpread > degenerateSpread, targetSpread > degenerateSpread else { return nil }

        let a = real / sourceSpread
        let b = imaginary / sourceSpread
        guard hypot(a, b) > 0 else { return nil }
        return FaceSimilarityTransform(
            a: a,
            b: b,
            tx: targetMeanX - (a * sourceMeanX - b * sourceMeanY),
            ty: targetMeanY - (b * sourceMeanX + a * sourceMeanY)
        )
    }

    /// Below this summed squared distance from the centroid (in squared pixels) a point set is
    /// treated as a single point.
    private static let degenerateSpread = 1e-9
}
