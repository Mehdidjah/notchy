import CoreGraphics
import Foundation
import Testing
@testable import Notchy

// MARK: - Helpers

private func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
    hypot(Double(first.x - second.x), Double(first.y - second.y))
}

private func expectClose(
    _ actual: CGPoint,
    _ expected: CGPoint,
    within tolerance: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        distance(actual, expected) <= tolerance,
        "\(actual) is \(distance(actual, expected)) px from \(expected)",
        sourceLocation: sourceLocation
    )
}

private func expectClose(
    _ actual: FaceSimilarityTransform,
    _ expected: FaceSimilarityTransform,
    within tolerance: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let error = [actual.a - expected.a, actual.b - expected.b, actual.tx - expected.tx, actual.ty - expected.ty]
        .map(abs).max() ?? 0
    #expect(error <= tolerance, "\(actual) differs from \(expected) by \(error)", sourceLocation: sourceLocation)
}

/// An sRGB image whose pixels come from `pixel(column, row)`, row 0 at the top.
private func makeImage(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for row in 0..<height {
        for column in 0..<width {
            let value = pixel(column, row)
            let index = (row * width + column) * 4
            bytes[index] = value.0
            bytes[index + 1] = value.1
            bytes[index + 2] = value.2
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

/// A black image with a soft red spot centred on each point (Face Check pixel convention).
private func spotImage(width: Int, height: Int, spots: [CGPoint], sigma: Double) -> CGImage {
    makeImage(width: width, height: height) { column, row in
        let x = Double(column) + 0.5
        let y = Double(row) + 0.5
        let intensity = spots.reduce(0.0) { total, spot in
            let dx = x - Double(spot.x)
            let dy = y - Double(spot.y)
            return total + exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
        }
        return (UInt8(min(255, (intensity * 255).rounded())), 0, 0)
    }
}

/// Intensity-weighted centre of the red channel within `radius` pixels of `near`.
private func redCentroid(in chip: FaceChipPixels, near: CGPoint, radius: Int) -> CGPoint {
    var total = 0.0
    var sumX = 0.0
    var sumY = 0.0
    let centreColumn = Int(near.x)
    let centreRow = Int(near.y)
    for row in max(0, centreRow - radius)...min(chip.size - 1, centreRow + radius) {
        for column in max(0, centreColumn - radius)...min(chip.size - 1, centreColumn + radius) {
            let weight = Double(chip.rgb(column: column, row: row).red)
            total += weight
            sumX += weight * (Double(column) + 0.5)
            sumY += weight * (Double(row) + 0.5)
        }
    }
    return CGPoint(x: sumX / total, y: sumY / total)
}

/// A simple upright face in Vision's terms: the image-left eye centred at (200, 200), the
/// image-right eye at (280, 200), a symmetric nose outline whose bottom is at (240, 265) and
/// lips below.
private func uprightFace() -> FaceLandmarkPoints {
    func eye(_ centreX: Double) -> [CGPoint] {
        [(-15.0, 0.0), (-7, -5), (7, -5), (15, 0), (7, 5), (-7, 5)].map {
            CGPoint(x: centreX + $0.0, y: 200 + $0.1)
        }
    }
    return FaceLandmarkPoints(
        leftEye: eye(280),
        rightEye: eye(200),
        nose: [(230.0, 228.0), (225, 255), (230, 262), (240, 265), (250, 262), (255, 255), (250, 228)]
            .map { CGPoint(x: $0.0, y: $0.1) },
        noseCrest: [(240.0, 205.0), (240, 220), (240, 235), (240, 250)].map { CGPoint(x: $0.0, y: $0.1) },
        outerLips: [
            (215.0, 295.0), (225, 288), (233, 285), (240, 286), (247, 285), (255, 288),
            (265, 295), (255, 302), (240, 306), (225, 302)
        ].map { CGPoint(x: $0.0, y: $0.1) }
    )
}

private func transformed(_ landmarks: FaceLandmarkPoints, by transform: FaceSimilarityTransform) -> FaceLandmarkPoints {
    FaceLandmarkPoints(
        leftEye: landmarks.leftEye.map(transform.apply),
        rightEye: landmarks.rightEye.map(transform.apply),
        nose: landmarks.nose.map(transform.apply),
        noseCrest: landmarks.noseCrest.map(transform.apply),
        outerLips: landmarks.outerLips.map(transform.apply)
    )
}

/// Five landmarks in dlib's pixel convention and where dlib's own chip mapping puts them.
struct DlibChipCase: Sendable, CustomTestStringConvertible {
    let name: String
    let landmarks: [CGPoint]
    let chip: [CGPoint]

    var testDescription: String { name }

    private static func points(_ values: [Double]) -> [CGPoint] {
        stride(from: 0, to: values.count, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
    }

    static let all: [DlibChipCase] = [
        DlibChipCase(
            name: "upright",
            landmarks: points([371, 205, 344, 207, 276, 205, 303, 207, 323, 258]),
            chip: points([
                110.418405, 45.832659, 89.472169, 47.448091, 36.702134, 46.056122,
                57.657779, 47.544533, 73.296958, 87.071486
            ])
        ),
        DlibChipCase(
            name: "rolled",
            landmarks: points([402, 251, 377, 242, 313, 220, 338, 230, 340, 284]),
            chip: points([
                110.468631, 46.568028, 89.651939, 46.348856, 36.629121, 46.557301,
                57.703420, 47.516402, 73.094085, 86.957350
            ])
        ),
        DlibChipCase(
            name: "large",
            landmarks: points([1020, 600, 900, 610, 580, 600, 700, 610, 790, 860]),
            chip: points([
                109.611790, 45.303498, 90.059575, 47.169199, 37.848615, 46.164138,
                57.439950, 47.560399, 72.607781, 88.158890
            ])
        )
    ]
}

/// A face placed in a synthetic image at a given scale and rotation.
struct SpotPlacementCase: Sendable, CustomTestStringConvertible {
    let scale: Double
    let rotation: Double
    let width: Int
    let height: Int
    let sigma: Double

    var testDescription: String { "scale \(scale)" }

    static let all = [
        SpotPlacementCase(scale: 1.3, rotation: 0.35, width: 640, height: 480, sigma: 2.0),
        SpotPlacementCase(scale: 3.2, rotation: -0.2, width: 1100, height: 950, sigma: 5.0)
    ]
}

// MARK: - Similarity transform

struct FaceCheckSimilarityTransformTests {
    @Test
    func leastSquaresFitRecoversAKnownTransformExactly() throws {
        let known = FaceSimilarityTransform(scale: 1.7, rotation: 0.4, translation: CGPoint(x: 120, y: -35))
        let source = [(3.0, 4.0), (-20, 11), (55, 70), (0, -40), (13, 13), (90, -5)].map { CGPoint(x: $0.0, y: $0.1) }
        let fitted = try #require(FaceSimilarityTransform.fit(from: source, to: source.map(known.apply)))
        expectClose(fitted, known, within: 1e-9)
        #expect(abs(fitted.scale - 1.7) < 1e-12)
        #expect(abs(fitted.rotation - 0.4) < 1e-12)
    }

    @Test
    func fitIsTheLeastSquaresAnswerForNoisyPoints() throws {
        // Two points pulled apart symmetrically: the best similarity keeps the midpoint, takes the
        // average spacing and no rotation.
        let source = [CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)]
        let target = [CGPoint(x: -2.2, y: 0), CGPoint(x: 2.2, y: 0), CGPoint(x: 0, y: 1.8), CGPoint(x: 0, y: -1.8)]
        let fitted = try #require(FaceSimilarityTransform.fit(from: source, to: target))
        expectClose(fitted, FaceSimilarityTransform(a: 2, b: 0, tx: 0, ty: 0), within: 1e-12)
    }

    @Test
    func inverseAndCompositionUndoEachOther() throws {
        let transform = FaceSimilarityTransform(scale: 0.6, rotation: -1.1, translation: CGPoint(x: -7, y: 42))
        let inverse = try #require(transform.inverse)
        expectClose(transform.followed(by: inverse), .identity, within: 1e-12)
        expectClose(inverse.followed(by: transform), .identity, within: 1e-12)

        let point = CGPoint(x: 13.5, y: -2.25)
        let other = FaceSimilarityTransform(scale: 3, rotation: 0.2, translation: CGPoint(x: 1, y: 2))
        expectClose(transform.followed(by: other).apply(point), other.apply(transform.apply(point)), within: 1e-12)
        expectClose(point.applying(transform.affineTransform), transform.apply(point), within: 1e-12)
    }

    @Test
    func degenerateInputHasNoFit() {
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 2), CGPoint(x: 3, y: 9)]
        let collapsed = Array(repeating: CGPoint(x: 4, y: 4), count: 3)
        #expect(FaceSimilarityTransform.fit(from: collapsed, to: points) == nil)
        #expect(FaceSimilarityTransform.fit(from: points, to: collapsed) == nil)
        #expect(FaceSimilarityTransform.fit(from: points, to: Array(points.prefix(2))) == nil)
        #expect(FaceSimilarityTransform.fit(from: [points[0]], to: [points[1]]) == nil)
        #expect(FaceSimilarityTransform.fit(from: points, to: [points[0], points[1], CGPoint(x: CGFloat.nan, y: 0)]) == nil)
        #expect(FaceSimilarityTransform(a: 0, b: 0, tx: 1, ty: 1).inverse == nil)
    }
}

// MARK: - Chip alignment

struct FaceCheckChipAlignmentTests {
    @Test
    func chipPointsSitInsideThePaddedTemplate() {
        let points = FaceChipTemplate.chipPoints()
        #expect(points.count == FaceChipLandmark.allCases.count)
        // The image-right outer eye corner: (0.25 + 0.8596) / 1.5 of the way across 150 pixels.
        expectClose(points[FaceChipLandmark.imageRightEyeOuterCorner.rawValue], CGPoint(x: 110.957, y: 46.350), within: 0.001)
        expectClose(points[FaceChipLandmark.noseBase.rawValue], CGPoint(x: 74.011, y: 87.780), within: 0.001)
        #expect(abs(FaceChipTemplate.noseBaseFractionFromTipToLip - 0.4956) < 0.0001)
    }

    @Test
    func pointsPlacedByAKnownSimilarityLandExactlyOnTheTemplate() throws {
        let placement = FaceSimilarityTransform(scale: 2.3, rotation: -0.35, translation: CGPoint(x: 410, y: 180))
        let template = FaceChipTemplate.chipPoints()
        let imagePoints = template.map(placement.apply)
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))

        for index in imagePoints.indices {
            let landed = alignment.imageToChip.apply(imagePoints[index])
            expectClose(landed, alignment.templatePoints[index], within: 1e-6)
            expectClose(landed, template[index], within: 0.5)
            expectClose(alignment.chipToImage.apply(alignment.templatePoints[index]), imagePoints[index], within: 1e-6)
        }
        #expect(alignment.residual < 1e-6)
        #expect(abs(alignment.fitScale - 2.3) < 1e-9)
        #expect(alignment.imagePoints == imagePoints)
    }

    @Test
    func aFaceAtTheChipsOwnScaleIsNotShrunk() throws {
        // dlib's one-pixel-narrower chip square only matters once the face is larger than the chip.
        let offset = FaceSimilarityTransform.translation(x: 12, y: 30)
        let template = FaceChipTemplate.chipPoints()
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: template.map(offset.apply)))
        expectClose(alignment.imageToChip, .translation(x: -12, y: -30), within: 1e-9)
        for (landed, nominal) in zip(alignment.templatePoints, template) {
            expectClose(landed, nominal, within: 1e-9)
        }
    }

    /// Reference values from dlib 20.0.1: `get_face_chip_details(det, 150, 0.25)` and the chip
    /// mapping it implies, for integer landmarks (dlib's pixel centres sit on whole numbers, so
    /// both sides are shifted by half a pixel here).
    @Test(arguments: DlibChipCase.all)
    func matchesDlibsOwnChipMapping(reference: DlibChipCase) throws {
        let imagePoints = reference.landmarks.map { CGPoint(x: $0.x + 0.5, y: $0.y + 0.5) }
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        for (point, expected) in zip(imagePoints, reference.chip) {
            expectClose(alignment.imageToChip.apply(point), CGPoint(x: expected.x + 0.5, y: expected.y + 0.5), within: 1e-4)
        }
    }

    @Test
    func degenerateFivePointsHaveNoAlignment() {
        let template = FaceChipTemplate.chipPoints()
        #expect(FaceChipAligner.alignment(fivePoints: Array(repeating: CGPoint(x: 50, y: 50), count: 5)) == nil)
        #expect(FaceChipAligner.alignment(fivePoints: Array(template.prefix(4))) == nil)
        #expect(FaceChipAligner.alignment(fivePoints: template + [template[0]]) == nil)
        #expect(FaceChipAligner.alignment(fivePoints: [CGPoint(x: CGFloat.infinity, y: 0)] + template.dropFirst()) == nil)
        #expect(FaceChipAligner.alignment(fivePoints: template, chipSize: 1) == nil)
        #expect(FaceChipAligner.alignment(fivePoints: template, padding: -0.1) == nil)
    }
}

// MARK: - Points from Vision landmarks

struct FaceCheckLandmarkPointTests {
    @Test
    func eyeCornersAndNoseBaseComeFromTheContours() throws {
        let points = try #require(FaceChipAligner.fivePoints(from: uprightFace(), correction: .none))
        expectClose(points[FaceChipLandmark.imageRightEyeOuterCorner.rawValue], CGPoint(x: 295, y: 200), within: 1e-9)
        expectClose(points[FaceChipLandmark.imageRightEyeInnerCorner.rawValue], CGPoint(x: 265, y: 200), within: 1e-9)
        expectClose(points[FaceChipLandmark.imageLeftEyeOuterCorner.rawValue], CGPoint(x: 185, y: 200), within: 1e-9)
        expectClose(points[FaceChipLandmark.imageLeftEyeInnerCorner.rawValue], CGPoint(x: 215, y: 200), within: 1e-9)
        expectClose(points[FaceChipLandmark.noseBase.rawValue], CGPoint(x: 240, y: 265), within: 1e-9)
    }

    @Test
    func whichEyeVisionCallsLeftDoesNotMatter() {
        var swapped = uprightFace()
        swap(&swapped.leftEye, &swapped.rightEye)
        #expect(FaceChipAligner.fivePoints(from: swapped) == FaceChipAligner.fivePoints(from: uprightFace()))
    }

    @Test
    func pointsFollowTheHeadThroughAnyRoll() throws {
        let face = uprightFace()
        let upright = try #require(FaceChipAligner.fivePoints(from: face))
        for angle in [0.3, Double.pi / 2, -2.0] {
            let roll = FaceSimilarityTransform(scale: 1, rotation: angle, translation: CGPoint(x: 37, y: -12))
            let rolled = try #require(FaceChipAligner.fivePoints(from: transformed(face, by: roll)))
            for (point, expected) in zip(rolled, upright.map(roll.apply)) {
                expectClose(point, expected, within: 1e-6)
            }
        }
    }

    @Test
    func measuredCorrectionMovesPointsTowardsDlibsLandmarks() throws {
        let raw = try #require(FaceChipAligner.fivePoints(from: uprightFace(), correction: .none))
        let corrected = try #require(FaceChipAligner.fivePoints(from: uprightFace(), correction: .measured))
        let span = 110.0 // outer corner to outer corner
        let measured = FaceLandmarkCorrection.measured
        // Image-right eye: lateral is +x. Image-left eye: lateral is −x. Down is +y.
        expectClose(
            corrected[0],
            CGPoint(x: raw[0].x + measured.outerCornerLateral * span, y: raw[0].y + measured.outerCornerDown * span),
            within: 1e-9
        )
        expectClose(
            corrected[3],
            CGPoint(x: raw[3].x - measured.innerCornerLateral * span, y: raw[3].y + measured.innerCornerDown * span),
            within: 1e-9
        )
        expectClose(corrected[4], CGPoint(x: raw[4].x, y: raw[4].y + measured.noseBaseDown * span), within: 1e-9)
    }

    @Test
    func withoutANoseOutlineTheBaseSitsBetweenTipAndUpperLip() throws {
        var face = uprightFace()
        face.nose = []
        let points = try #require(FaceChipAligner.fivePoints(from: face, correction: .measured))
        // Tip (240, 250); upper-lip top at the mouth's middle (240, 286).
        let expectedY = 250 + FaceChipTemplate.noseBaseFractionFromTipToLip * 36
        expectClose(points[FaceChipLandmark.noseBase.rawValue], CGPoint(x: 240, y: expectedY), within: 1e-9)
    }

    @Test
    func incompleteOrImplausibleLandmarksAreRejected() {
        var noEye = uprightFace()
        noEye.leftEye = []
        #expect(FaceChipAligner.fivePoints(from: noEye) == nil)

        var samePlace = uprightFace()
        samePlace.leftEye = samePlace.rightEye
        #expect(FaceChipAligner.fivePoints(from: samePlace) == nil)

        var nothingBelow = uprightFace()
        nothingBelow.nose = []
        nothingBelow.noseCrest = []
        nothingBelow.outerLips = []
        #expect(FaceChipAligner.fivePoints(from: nothingBelow) == nil)

        var noseAboveEyes = uprightFace()
        noseAboveEyes.nose = noseAboveEyes.nose.map { CGPoint(x: $0.x, y: $0.y - 120) }
        #expect(FaceChipAligner.fivePoints(from: noseAboveEyes) == nil)

        var eyesAlongTheFace = uprightFace()
        eyesAlongTheFace.leftEye = eyesAlongTheFace.leftEye.map { CGPoint(x: $0.x - 40, y: $0.y + 100) }
        #expect(FaceChipAligner.fivePoints(from: eyesAlongTheFace) == nil)

        #expect(FaceChipAligner.alignment(for: FaceLandmarkPoints()) == nil)
        #expect(FaceChipAligner.alignment(for: uprightFace()) != nil)
    }

    @Test
    func flippingMeasuresFromTheTopEdge() {
        let face = FaceLandmarkPoints(leftEye: [CGPoint(x: 10, y: 380)], outerLips: [CGPoint(x: 5, y: 0)])
        let flipped = face.flippedVertically(imageHeight: 480)
        #expect(flipped.leftEye == [CGPoint(x: 10, y: 100)])
        #expect(flipped.outerLips == [CGPoint(x: 5, y: 480)])
        #expect(flipped.nose.isEmpty)
    }
}

// MARK: - Rendering

struct FaceCheckChipRendererTests {
    @Test
    func unscaledUnrotatedChipCopiesImagePixelsExactly() throws {
        let image = makeImage(width: 300, height: 240) { column, row in
            (UInt8((column * 7 + row * 3) % 256), UInt8((column * 5 + row * 11) % 256), UInt8((column ^ row) & 255))
        }
        let offset = CGPoint(x: 61, y: 37)
        let imagePoints = FaceChipTemplate.chipPoints().map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        let chip = try #require(FaceChipRenderer.render(image, alignment: alignment))
        #expect(chip.size == 150)

        var worst = 0
        for row in stride(from: 0, to: 150, by: 7) {
            for column in stride(from: 0, to: 150, by: 5) {
                let got = chip.rgb(column: column, row: row)
                let sourceColumn = column + 61
                let sourceRow = row + 37
                let want = (
                    (sourceColumn * 7 + sourceRow * 3) % 256,
                    (sourceColumn * 5 + sourceRow * 11) % 256,
                    (sourceColumn ^ sourceRow) & 255
                )
                worst = max(worst, abs(Int(got.red) - want.0), abs(Int(got.green) - want.1), abs(Int(got.blue) - want.2))
            }
        }
        // Rounding in the fit can put a sample a hair before a pixel centre; truncation then
        // costs at most one level, exactly as in dlib.
        #expect(worst <= 1)
    }

    @Test(arguments: SpotPlacementCase.all)
    func landmarksLandOnTheTemplateInTheRenderedChip(placementCase: SpotPlacementCase) throws {
        let scale = placementCase.scale
        let width = placementCase.width
        let height = placementCase.height
        let rotation = placementCase.rotation
        let sigma = placementCase.sigma
        let template = FaceChipTemplate.chipPoints()
        let placement = FaceSimilarityTransform(
            scale: scale,
            rotation: rotation,
            translation: CGPoint(x: Double(width) / 2 - 75 * scale, y: Double(height) / 2 - 75 * scale)
        )
        let imagePoints = template.map(placement.apply)
        let image = spotImage(width: width, height: height, spots: imagePoints, sigma: sigma)
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        let levels = FaceChipRenderer.pyramidLevels(fitScale: alignment.fitScale)
        #expect(levels == (scale > 2 ? 1 : 0))
        // Each halving dlib does shifts what the chip shows by half a source pixel right and up
        // (its filter is centred half a pixel from where it places the chip); a spot appears
        // where that shifted point maps.
        let shift = 0.5 * Double((1 << levels) - 1)
        let chip = try #require(FaceChipRenderer.render(image, alignment: alignment))
        for (spot, target) in zip(imagePoints, alignment.templatePoints) {
            let expected = alignment.imageToChip.apply(CGPoint(x: spot.x + shift, y: spot.y - shift))
            expectClose(expected, target, within: 0.5)
            expectClose(redCentroid(in: chip, near: target, radius: 7), expected, within: 0.1)
        }
    }

    @Test
    func chipAreasOutsideTheImageAreBlack() throws {
        let image = makeImage(width: 200, height: 200) { _, _ in (128, 128, 128) }
        // Put the chip's top-left corner 40 px outside the image's top-left corner.
        let imagePoints = FaceChipTemplate.chipPoints().map { CGPoint(x: $0.x - 40, y: $0.y - 40) }
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        let chip = try #require(FaceChipRenderer.render(image, alignment: alignment))
        #expect(chip.rgb(column: 5, row: 5) == (0, 0, 0))
        #expect(chip.rgb(column: 100, row: 100) == (128, 128, 128))
        #expect(chip.rgb(column: 100, row: 10) == (0, 0, 0))
    }

    @Test
    func chipEntirelyOutsideTheImageIsNotRendered() throws {
        let image = makeImage(width: 100, height: 100) { _, _ in (10, 20, 30) }
        let imagePoints = FaceChipTemplate.chipPoints().map { CGPoint(x: $0.x + 500, y: $0.y + 500) }
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        #expect(FaceChipRenderer.render(image, alignment: alignment) == nil)
    }

    @Test
    func renderedImageIsAnOpaqueRGBChip() throws {
        let image = makeImage(width: 300, height: 300) { column, row in
            (column < 150 ? 200 : 20, row < 150 ? 180 : 40, 90)
        }
        let imagePoints = FaceChipTemplate.chipPoints().map { CGPoint(x: $0.x + 75, y: $0.y + 75) }
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: imagePoints))
        let chipImage = try #require(FaceChipRenderer.renderImage(image, alignment: alignment))
        #expect(chipImage.width == 150)
        #expect(chipImage.height == 150)
        #expect(chipImage.alphaInfo == .noneSkipLast)

        // Read it back: top-left quadrant of the chip is the image's red-and-green area.
        let context = try #require(CGContext(
            data: nil, width: 150, height: 150, bitsPerComponent: 8, bytesPerRow: 600,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(chipImage, in: CGRect(x: 0, y: 0, width: 150, height: 150))
        let bytes = try #require(context.data).bindMemory(to: UInt8.self, capacity: 600 * 150)
        let topLeft = (10 * 150 + 10) * 4
        let bottomRight = (140 * 150 + 140) * 4
        #expect((bytes[topLeft], bytes[topLeft + 1], bytes[topLeft + 2]) == (200, 180, 90))
        #expect((bytes[bottomRight], bytes[bottomRight + 1], bytes[bottomRight + 2]) == (20, 40, 90))
    }

    @Test
    func pyramidDepthFollowsDlib() {
        // dlib halves while the square, halved again, still spans more than 150 pixels counting
        // both edges: (150 × scale − 1) / 2 + 1 > 150 first holds just below a scale of 2.
        #expect(FaceChipRenderer.pyramidLevels(fitScale: 0.5) == 0)
        #expect(FaceChipRenderer.pyramidLevels(fitScale: 1.99) == 0)
        #expect(FaceChipRenderer.pyramidLevels(fitScale: 2.0) == 1)
        #expect(FaceChipRenderer.pyramidLevels(fitScale: 3.9) == 1)
        #expect(FaceChipRenderer.pyramidLevels(fitScale: 4.0) == 2)
        #expect(FaceChipRenderer.pyramidLevels(fitScale: .infinity) == 0)
    }

    @Test
    func halvingUsesDlibsFilter() throws {
        // A single bright column: dlib's 1 4 6 4 1 filter spreads it over neighbouring output
        // columns in those proportions (integer maths, truncated).
        let image = makeImage(width: 600, height: 600) { column, _ in column == 300 ? (255, 255, 255) : (0, 0, 0) }
        // A face large enough for one halving, upright and centred.
        let placement = FaceSimilarityTransform(scale: 3, rotation: 0, translation: CGPoint(x: 75, y: 75))
        let alignment = try #require(FaceChipAligner.alignment(fivePoints: FaceChipTemplate.chipPoints().map(placement.apply)))
        #expect(FaceChipRenderer.pyramidLevels(fitScale: alignment.fitScale) == 1)
        let chip = try #require(FaceChipRenderer.render(image, alignment: alignment))
        let row = (0..<150).map { Int(chip.rgb(column: $0, row: 75).red) }
        // The line survives as a soft peak, never brighter than the filter's centre weight allows.
        let peak = try #require(row.max())
        #expect(peak > 0)
        #expect(peak <= 255 * 6 / 16)
        #expect(chip.rgb(column: 0, row: 75) == (0, 0, 0))
    }
}
