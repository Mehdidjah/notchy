import CoreGraphics
import Foundation

// MARK: - Landmarks

/// Face landmarks from Vision, copied into plain points so they can leave the Vision request.
///
/// Vision's landmark objects are not `Sendable`, so the adapter converts each region with
/// `pointsInImage(imageSize:)` and flips it into Face Check's top-left pixel convention (see
/// `FaceChipTemplate` and `flippedVertically(imageHeight:)`) before anything leaves the
/// pipeline. `leftEye` and `rightEye` keep Vision's names, but the aligner sorts the eyes by where
/// they sit in the picture, so it never depends on which eye Vision calls left.
///
/// Vision's median line is left out on purpose. Measured against dlib's own landmarks, its one
/// point near the nose base coincides with the bottom of the nose outline, which `nose` already
/// carries; the rest run down the bridge, lips and chin, which dlib's five points do not use.
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
    /// `Σ conj(source)·target / Σ |source|²`. dlib fits its face chips the same way, so the two
    /// agree to rounding. Returns `nil` when the sets differ in size, hold fewer than two points,
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

// MARK: - Alignment

/// How one face maps onto dlib's 150 × 150 chip. Both directions are kept so the renderer and
/// any landmark overlay can use whichever they need without inverting again.
struct FaceChipAlignment: Equatable, Sendable {
    let chipSize: Int
    /// Image pixels (Face Check convention) to chip pixels (same convention).
    let imageToChip: FaceSimilarityTransform
    let chipToImage: FaceSimilarityTransform
    /// The five image points the fit used, in `FaceChipLandmark` order.
    let imagePoints: [CGPoint]
    /// Where dlib's template puts the five landmarks in this chip.
    let templatePoints: [CGPoint]
    /// dlib's own fit from its template (`unit × size`) onto the image, in dlib's pixel
    /// convention (pixel centres on whole numbers). The renderer rebuilds dlib's chip rectangle
    /// and image pyramid from it.
    let templateToImage: FaceSimilarityTransform
    /// Root-mean-square distance, in chip pixels, between where the five points land and
    /// `templatePoints`. Small for a frontal face; large when the landmarks do not look like a
    /// face from the front (a strong profile, or landmarks Vision got wrong), which is a reason
    /// to skip the frame rather than embed it.
    let residual: Double

    /// How many image pixels one chip pixel covers.
    var imagePixelsPerChipPixel: Double { chipToImage.scale }

    /// Scale of dlib's own fit: image pixels per template pixel.
    var fitScale: Double { templateToImage.scale }
}

/// Systematic offsets between Vision's landmarks and the ones dlib aligns with, removed before
/// fitting so Face Check's chips land where dlib's own would.
///
/// Offsets are fractions of the distance between the two outer eye corners. `lateral` points
/// away from the middle of the face and `down` towards the chin.
///
/// Measured on 31 faces with 42–167 px between the outer eye corners (dlib's example face
/// images), comparing the points below with dlib's own five-point landmarks. Vision's eye
/// contours sit slightly high and their inner ends slightly towards the nose; the bottom of
/// Vision's nose outline sits slightly above dlib's nose base. The left/right halves were
/// averaged so the correction stays mirror-symmetric. With it, chips differ from dlib's own by a
/// median of about 1 px (1.2–1.8 px when estimated on one half of the faces and checked on the
/// other) instead of about 2.2 px. Faces under about 40 px between the outer eye corners land
/// 5 px or more away whatever the correction, so the pipeline should treat them as too far from
/// the camera. Re-measure on webcam frames when calibrating thresholds.
struct FaceLandmarkCorrection: Equatable, Sendable {
    var outerCornerLateral: Double
    var outerCornerDown: Double
    var innerCornerLateral: Double
    var innerCornerDown: Double
    /// Applied only when the nose base comes from Vision's nose outline.
    var noseBaseDown: Double

    static let none = FaceLandmarkCorrection(
        outerCornerLateral: 0,
        outerCornerDown: 0,
        innerCornerLateral: 0,
        innerCornerDown: 0,
        noseBaseDown: 0
    )

    static let measured = FaceLandmarkCorrection(
        outerCornerLateral: 0.003,
        outerCornerDown: 0.029,
        innerCornerLateral: 0.019,
        innerCornerDown: 0.019,
        noseBaseDown: 0.037
    )
}

/// Lines a face up with dlib's face-chip template.
///
/// dlib aligns with five points: the outer and inner corner of each eye and the base of the nose.
/// Vision has no such points, so they are derived from its contours:
/// - **Eye corners**: the two ends of each eye contour along the line through both eyes.
/// - **Nose base**: the bottom of the nose outline, taken under the outline's own middle. The
///   lowest point of the nose crest is the nose *tip*, about a sixth of the eye-corner distance
///   higher; using it would shift chips by about 9 px, so it is only a fallback (moved half way
///   towards the top of the upper lip, as in dlib's mean face) when there is no nose outline.
///
/// All of this is plain arithmetic on value types, safe to call from any thread.
enum FaceChipAligner {
    /// The alignment for a face Vision found, or `nil` when the landmarks are too incomplete or
    /// too inconsistent to place a face.
    static func alignment(
        for landmarks: FaceLandmarkPoints,
        correction: FaceLandmarkCorrection = .measured,
        chipSize: Int = FaceChipTemplate.chipSize,
        padding: Double = FaceChipTemplate.padding
    ) -> FaceChipAlignment? {
        guard let points = fivePoints(from: landmarks, correction: correction) else { return nil }
        return alignment(fivePoints: points, chipSize: chipSize, padding: padding)
    }

    /// dlib's `get_face_chip_details` followed by its chip mapping, for five points already in
    /// `FaceChipLandmark` order.
    ///
    /// dlib fits its padded template (`unit × size`, pixel centres on whole numbers) onto the
    /// image points with a similarity of scale `s`. It then keeps that fit's centre and angle but
    /// builds the chip from a square `size × s` wide that it measures the way it measures integer
    /// rectangles, one pixel short (`right − left + 1`), and maps that square's corners onto the
    /// chip's corner pixel centres, 0 and `size − 1`. The net effect is the fitted mapping scaled
    /// about the chip's centre by `(size − 1)·s / (size·s − 1)`: no change for a face at the
    /// chip's own scale, approaching `(size − 1) / size` for large faces. Reproducing it, plus the
    /// half-pixel step between dlib's pixel convention and Face Check's, gives chips that match
    /// dlib's own to rounding.
    static func alignment(
        fivePoints points: [CGPoint],
        chipSize: Int = FaceChipTemplate.chipSize,
        padding: Double = FaceChipTemplate.padding
    ) -> FaceChipAlignment? {
        guard points.count == FaceChipLandmark.allCases.count, chipSize >= 2 else { return nil }
        guard padding >= 0, padding.isFinite else { return nil }

        let size = Double(chipSize)
        let template = FaceChipTemplate.fitPoints(size: chipSize, padding: padding)
        let dlibImagePoints = points.map { CGPoint(x: $0.x - 0.5, y: $0.y - 0.5) }
        guard let templateToImage = FaceSimilarityTransform.fit(from: template, to: dlibImagePoints),
              let imageToTemplate = templateToImage.inverse
        else { return nil }

        let fitScale = templateToImage.scale
        guard size * fitScale > 1 else { return nil }
        let shrink = (size - 1) * fitScale / (size * fitScale - 1)
        let toCentre = FaceSimilarityTransform.translation(x: -size / 2, y: -size / 2)
        let fromCentre = FaceSimilarityTransform.translation(x: size / 2, y: size / 2)

        // dlib's convention → template units → shrink about the centre → Face Check's convention.
        let imageToChip = FaceSimilarityTransform.translation(x: -0.5, y: -0.5)
            .followed(by: imageToTemplate)
            .followed(by: toCentre)
            .followed(by: .scaling(shrink))
            .followed(by: fromCentre)
        guard let chipToImage = imageToChip.inverse else { return nil }

        let templateInChip = template.map(toCentre.followed(by: .scaling(shrink)).followed(by: fromCentre).apply)
        let squaredError = zip(points, templateInChip).reduce(0.0) { total, pair in
            let landed = imageToChip.apply(pair.0)
            let dx = Double(landed.x - pair.1.x)
            let dy = Double(landed.y - pair.1.y)
            return total + dx * dx + dy * dy
        }
        return FaceChipAlignment(
            chipSize: chipSize,
            imageToChip: imageToChip,
            chipToImage: chipToImage,
            imagePoints: points,
            templatePoints: templateInChip,
            templateToImage: templateToImage,
            residual: (squaredError / Double(points.count)).squareRoot()
        )
    }

    /// The five dlib landmarks derived from Vision's contours, in `FaceChipLandmark` order, or
    /// `nil` when an eye is missing, nothing below the eyes shows which way is down, or the
    /// points do not form a plausible face.
    static func fivePoints(
        from landmarks: FaceLandmarkPoints,
        correction: FaceLandmarkCorrection = .measured
    ) -> [CGPoint]? {
        let eyeA = PlanePoint.finite(landmarks.leftEye)
        let eyeB = PlanePoint.finite(landmarks.rightEye)
        let nose = PlanePoint.finite(landmarks.nose)
        let crest = PlanePoint.finite(landmarks.noseCrest)
        let lips = PlanePoint.finite(landmarks.outerLips)
        guard eyeA.count >= 2, eyeB.count >= 2,
              let centreA = PlanePoint.mean(eyeA),
              let centreB = PlanePoint.mean(eyeB)
        else { return nil }

        // Something below the eyes shows which way is down, and so which eye is on which side of
        // the picture, whatever the head's roll.
        let eyeMiddle = (centreA + centreB) * 0.5
        guard let below = PlanePoint.mean(lips) ?? PlanePoint.mean(nose) ?? PlanePoint.mean(crest),
              let roughDown = (below - eyeMiddle).normalized
        else { return nil }
        let roughRight = PlanePoint(x: roughDown.y, y: -roughDown.x)
        let imageRightIsB = centreB.dot(roughRight) >= centreA.dot(roughRight)
        let imageLeftEye = imageRightIsB ? eyeA : eyeB
        let imageRightEye = imageRightIsB ? eyeB : eyeA

        // `across` runs from the image-left eye to the image-right eye; `down` is square to it.
        guard let across = ((imageRightIsB ? centreB : centreA) - (imageRightIsB ? centreA : centreB)).normalized
        else { return nil }
        let down = PlanePoint(x: -across.y, y: across.x)
        // The eyes must lie across the face, not along it.
        guard roughDown.dot(down) > 0.5 else { return nil }

        var outerRight = imageRightEye.extreme(along: across, largest: true)
        var innerRight = imageRightEye.extreme(along: across, largest: false)
        var outerLeft = imageLeftEye.extreme(along: across, largest: false)
        var innerLeft = imageLeftEye.extreme(along: across, largest: true)
        let eyeSpan = (outerRight - outerLeft).length
        guard eyeSpan > minimumSpan else { return nil }

        var noseBase: PlanePoint
        if nose.count >= 3 {
            let middle = nose.reduce(0) { $0 + $1.dot(across) } / Double(nose.count)
            let depth = nose.map { $0.dot(down) }.max() ?? 0
            noseBase = across * middle + down * (depth + correction.noseBaseDown * eyeSpan)
        } else if let estimate = noseBaseFromCrestAndLips(crest: crest, lips: lips, across: across, down: down) {
            noseBase = estimate
        } else {
            return nil
        }
        guard (noseBase - eyeMiddle).dot(down) > 0 else { return nil }

        outerRight = outerRight + (across * correction.outerCornerLateral + down * correction.outerCornerDown) * eyeSpan
        outerLeft = outerLeft + (across * -correction.outerCornerLateral + down * correction.outerCornerDown) * eyeSpan
        innerRight = innerRight + (across * correction.innerCornerLateral + down * correction.innerCornerDown) * eyeSpan
        innerLeft = innerLeft + (across * -correction.innerCornerLateral + down * correction.innerCornerDown) * eyeSpan

        return [outerRight, innerRight, outerLeft, innerLeft, noseBase].map(\.cgPoint)
    }

    /// Below this many pixels two landmarks are treated as the same point.
    private static let minimumSpan = 1e-3

    /// Estimates the nose base from the nose tip (lowest crest point) and the top of the upper
    /// lip at the mouth's middle, using where the base sits between them in dlib's mean face.
    private static func noseBaseFromCrestAndLips(
        crest: [PlanePoint],
        lips: [PlanePoint],
        across: PlanePoint,
        down: PlanePoint
    ) -> PlanePoint? {
        guard !crest.isEmpty, lips.count >= 4,
              let lipTop = upperLipTopMiddle(lips, across: across, down: down)
        else { return nil }
        let tip = crest.extreme(along: down, largest: true)
        return tip + (lipTop - tip) * FaceChipTemplate.noseBaseFractionFromTipToLip
    }

    /// The top edge of the upper lip at the mouth's middle, read off the outer lip contour by
    /// interpolating between the nearest upper-lip points on either side of the middle.
    private static func upperLipTopMiddle(
        _ lips: [PlanePoint],
        across: PlanePoint,
        down: PlanePoint
    ) -> PlanePoint? {
        let leftCorner = lips.extreme(along: across, largest: false)
        let rightCorner = lips.extreme(along: across, largest: true)
        let middle = (leftCorner.dot(across) + rightCorner.dot(across)) / 2
        let cornerDepth = (leftCorner.dot(down) + rightCorner.dot(down)) / 2
        let upper = lips.filter { $0.dot(down) < cornerDepth }
        let before = upper.filter { $0.dot(across) <= middle }.max { $0.dot(across) < $1.dot(across) }
        let after = upper.filter { $0.dot(across) >= middle }.min { $0.dot(across) < $1.dot(across) }

        let depth: Double
        switch (before, after) {
        case let (start?, end?):
            let run = end.dot(across) - start.dot(across)
            if run < minimumSpan {
                depth = start.dot(down)
            } else {
                let t = (middle - start.dot(across)) / run
                depth = start.dot(down) + t * (end.dot(down) - start.dot(down))
            }
        case let (only?, nil), let (nil, only?):
            depth = only.dot(down)
        case (nil, nil):
            return nil
        }
        return across * middle + down * depth
    }
}

// MARK: - Plane maths

/// A point or direction in Double precision, private to the aligner's arithmetic.
private struct PlanePoint {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    var length: Double { hypot(x, y) }

    var normalized: PlanePoint? {
        let length = length
        guard length > 1e-9, length.isFinite else { return nil }
        return PlanePoint(x: x / length, y: y / length)
    }

    func dot(_ other: PlanePoint) -> Double { x * other.x + y * other.y }

    static func + (lhs: PlanePoint, rhs: PlanePoint) -> PlanePoint { PlanePoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: PlanePoint, rhs: PlanePoint) -> PlanePoint { PlanePoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: PlanePoint, rhs: Double) -> PlanePoint { PlanePoint(x: lhs.x * rhs, y: lhs.y * rhs) }

    static func finite(_ points: [CGPoint]) -> [PlanePoint] {
        points.filter { $0.x.isFinite && $0.y.isFinite }.map(PlanePoint.init)
    }

    static func mean(_ points: [PlanePoint]) -> PlanePoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(PlanePoint(x: 0, y: 0), +)
        return sum * (1 / Double(points.count))
    }
}

private extension Array where Element == PlanePoint {
    /// The point furthest along `axis` (or furthest against it). The array must not be empty.
    func extreme(along axis: PlanePoint, largest: Bool) -> PlanePoint {
        let ordered = largest
            ? self.max { $0.dot(axis) < $1.dot(axis) }
            : self.min { $0.dot(axis) < $1.dot(axis) }
        return ordered ?? PlanePoint(x: 0, y: 0)
    }
}
