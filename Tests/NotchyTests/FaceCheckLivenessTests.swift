import CoreGraphics
import Foundation
import Testing
@testable import Notchy

private func livenessLandmarks(eyeHeight: Double = 5, noseShift: Double = 0) -> FaceLandmarkPoints {
    func eye(_ x: Double) -> [CGPoint] {
        [(-15.0, 0.0), (-7, -eyeHeight), (7, -eyeHeight), (15, 0), (7, eyeHeight), (-7, eyeHeight)]
            .map { CGPoint(x: x + $0.0, y: 150 + $0.1) }
    }
    return FaceLandmarkPoints(
        leftEye: eye(220), rightEye: eye(140),
        nose: [(170.0, 180.0), (165, 202), (180, 215), (195, 202), (190, 180)]
            .map { CGPoint(x: $0.0 + noseShift, y: $0.1) },
        noseCrest: [(180.0, 160.0), (180, 180), (180, 200)]
            .map { CGPoint(x: $0.0 + noseShift, y: $0.1) },
        outerLips: [(155.0, 240.0), (170, 232), (190, 232), (205, 240), (190, 248), (170, 248)]
            .map { CGPoint(x: $0.0, y: $0.1) }
    )
}

private func livenessObservation(
    eyeHeight: Double = 5, yaw: Double = 0, noseShift: Double = 0
) -> FaceLivenessObservation {
    FaceLivenessObservation(
        geometry: FaceLivenessGeometry.measure(livenessLandmarks(eyeHeight: eyeHeight, noseShift: noseShift))!,
        yaw: yaw, pitch: 0, quality: 0.8,
        glare: FaceGlareMeasurement(brightFraction: 0.01, largestBrightRegionFraction: 0.002, nativeCropWidth: 180),
        enclosingDevice: false
    )
}

private func blinkingSequence(_ tracker: inout FaceLivenessTracker) {
    _ = tracker.consume(livenessObservation(), timestamp: 0)
    _ = tracker.consume(livenessObservation(), timestamp: 0.12)
    #expect(tracker.consume(livenessObservation(), timestamp: 0.24) == .collecting(.blink))
    #expect(tracker.consume(livenessObservation(eyeHeight: 2), timestamp: 0.4) == .collecting(.blink))
    #expect(tracker.consume(livenessObservation(), timestamp: 0.56) == .collecting(.turn(tracker.direction)))
}

@discardableResult
private func turnAndReturn(_ tracker: inout FaceLivenessTracker, from start: Double = 0.7) -> FaceLivenessResult {
    let sign = tracker.direction.sign
    let turn = livenessObservation(yaw: sign * 22, noseShift: sign * 7)
    _ = tracker.consume(turn, timestamp: start)
    _ = tracker.consume(turn, timestamp: start + 0.15)
    #expect(tracker.consume(turn, timestamp: start + 0.3) == .collecting(.lookBackAtCamera))
    _ = tracker.consume(livenessObservation(), timestamp: start + 0.5)
    return tracker.consume(livenessObservation(), timestamp: start + 0.65)
}

struct FaceCheckLivenessGeometryTests {
    @Test
    func extractionIsInvariantToTranslationScaleAndRoll() throws {
        let original = livenessLandmarks()
        let transform = FaceSimilarityTransform(scale: 1.3, rotation: 0.21, translation: CGPoint(x: 12, y: 50))
        let moved = FaceLandmarkPoints(
            leftEye: original.leftEye.map(transform.apply), rightEye: original.rightEye.map(transform.apply),
            nose: original.nose.map(transform.apply), noseCrest: original.noseCrest.map(transform.apply),
            outerLips: original.outerLips.map(transform.apply)
        )
        let a = try #require(FaceLivenessGeometry.measure(original))
        let b = try #require(FaceLivenessGeometry.measure(moved))
        #expect(abs(a.leftEyeOpenness - b.leftEyeOpenness) < 1e-8)
        #expect(abs(a.rightEyeOpenness - b.rightEyeOpenness) < 1e-8)
        #expect(abs(a.noseOffset - b.noseOffset) < 1e-8)
        #expect(FaceLivenessGeometry.nonPlanarNoseMotion(from: a, to: b) == 0)
    }

    @Test
    func incompleteTinyOrInvalidLandmarksDoNotYieldEvidence() {
        #expect(FaceLivenessGeometry.measure(FaceLandmarkPoints()) == nil)
        var bad = livenessLandmarks()
        bad.noseCrest = []
        #expect(FaceLivenessGeometry.measure(bad) == nil)
        bad = livenessLandmarks()
        bad.leftEye[0].x = .nan
        #expect(FaceLivenessGeometry.measure(bad) == nil)
        bad = livenessLandmarks()
        bad.leftEye = bad.leftEye.map { CGPoint(x: $0.x - 60, y: $0.y) }
        #expect(FaceLivenessGeometry.measure(bad) == nil)
    }

    @Test
    func aPerspectiveWarpOfAFlatFaceDoesNotProduceDepth() throws {
        let a = livenessObservation().geometry
        func warp(_ p: CGPoint) -> CGPoint {
            let divisor = 0.13 * p.x + 0.09 * p.y + 1
            return CGPoint(x: (0.9 * p.x + 0.06 * p.y + 0.07) / divisor,
                           y: (0.04 * p.x + 1.03 * p.y + 0.02) / divisor)
        }
        var b = a
        b.planePoints = a.planePoints.map(warp)
        b.nosePoints = a.nosePoints.map(warp)
        #expect(try #require(FaceLivenessGeometry.nonPlanarNoseMotion(from: a, to: b)) == 0)
    }

    @Test
    func aNoseMovingOffTheReferencePlaneProducesSignedEvidence() throws {
        let a = livenessObservation().geometry
        for direction in FaceLivenessDirection.allCases {
            let b = livenessObservation(yaw: 22 * direction.sign, noseShift: 7 * direction.sign).geometry
            let displacement = try #require(FaceLivenessGeometry.nonPlanarNoseMotion(from: a, to: b))
            #expect(displacement * direction.sign > 0.08)
        }
        var degenerate = a
        degenerate.planePoints = Array(repeating: .zero, count: 8)
        #expect(FaceLivenessGeometry.nonPlanarNoseMotion(from: degenerate, to: a) == nil)
    }

    @Test
    func uncorrelatedNoseJitterIsNotDepth() {
        let a = livenessObservation().geometry
        var b = a
        b.nosePoints[0].x += 0.08
        b.nosePoints[1].x -= 0.08
        #expect(FaceLivenessGeometry.nonPlanarNoseMotion(from: a, to: b) == 0)
    }
}

struct FaceCheckLivenessSequenceTests {
    @Test(arguments: FaceLivenessDirection.allCases)
    func blinkTurnAndReturnAreAllRequired(_ direction: FaceLivenessDirection) {
        var tracker = FaceLivenessTracker(direction: direction)
        blinkingSequence(&tracker)
        #expect(turnAndReturn(&tracker) == .passed)
    }

    @Test
    func staticFramesAndYawWithoutNoseParallaxNeverPass() {
        var tracker = FaceLivenessTracker(direction: .right)
        for index in 0..<90 {
            #expect(tracker.consume(livenessObservation(), timestamp: Double(index) * 0.1) != .passed)
        }
        tracker = FaceLivenessTracker(direction: .right)
        blinkingSequence(&tracker)
        for index in 0..<30 {
            let result = tracker.consume(livenessObservation(yaw: 22 * tracker.direction.sign), timestamp: 0.7 + Double(index) * 0.1)
            #expect(result == .collecting(.turn(.right)))
        }
    }

    @Test
    func replayingTheOppositeDirectionDoesNotAdvance() {
        var tracker = FaceLivenessTracker(direction: .left)
        blinkingSequence(&tracker)
        for index in 0..<12 {
            let wrongTurn = livenessObservation(yaw: -22 * tracker.direction.sign, noseShift: -7 * tracker.direction.sign)
            #expect(tracker.consume(wrongTurn, timestamp: 0.7 + Double(index) * 0.1) == .collecting(.turn(.left)))
        }
    }

    @Test
    func rigidMotionWithAChangedYawEstimateCannotPass() {
        var tracker = FaceLivenessTracker(direction: .right)
        blinkingSequence(&tracker)
        var frame = livenessObservation(yaw: 22 * tracker.direction.sign)
        let transform = FaceSimilarityTransform(scale: 0.9, rotation: 0.08,
                                                 translation: CGPoint(x: 0.1 * tracker.direction.sign, y: 0.02))
        frame.geometry.planePoints = frame.geometry.planePoints.map(transform.apply)
        frame.geometry.nosePoints = frame.geometry.nosePoints.map(transform.apply)
        for index in 0..<6 {
            #expect(tracker.consume(frame, timestamp: 0.7 + Double(index) * 0.1) == .collecting(.turn(.right)))
        }
    }

    @Test
    func losingTheFaceDiscardsTheCompletedBlink() {
        var tracker = FaceLivenessTracker(direction: .right)
        blinkingSequence(&tracker)
        #expect(tracker.consume(nil, timestamp: 0.65) == .collecting(.lookAtCamera))
        for index in 0..<6 {
            let turn = livenessObservation(yaw: 22 * tracker.direction.sign, noseShift: 7 * tracker.direction.sign)
            #expect(tracker.consume(turn, timestamp: 0.7 + Double(index) * 0.1) != .passed)
        }
        #expect(tracker.consume(livenessObservation(), timestamp: 1.4) == .collecting(.lookAtCamera))
    }

    @Test
    func frameGapsDoNotJoinSeparatePerformancesIntoOneChallenge() {
        var tracker = FaceLivenessTracker(direction: .right)
        blinkingSequence(&tracker)
        let turn = livenessObservation(yaw: 22 * tracker.direction.sign, noseShift: 7 * tracker.direction.sign)
        #expect(tracker.consume(turn, timestamp: 2) == .collecting(.lookAtCamera))
        #expect(tracker.consume(livenessObservation(), timestamp: 2.2) == .collecting(.lookAtCamera))
    }

    @Test
    func invalidClocksRejectInsteadOfReusingEvidence() {
        for timestamp in [Double.nan, Double.infinity, -1, 0] {
            var tracker = FaceLivenessTracker(direction: .right)
            _ = tracker.consume(livenessObservation(), timestamp: 0)
            #expect(tracker.consume(livenessObservation(), timestamp: timestamp) == .rejected(.invalidTiming))
            #expect(tracker.consume(livenessObservation(), timestamp: 1) == .rejected(.invalidTiming))
        }
    }

    @Test
    func winkingAndStartingWithClosedEyesDoNotCountAsABlink() {
        var tracker = FaceLivenessTracker(direction: .right)
        for index in 0..<8 {
            #expect(tracker.consume(livenessObservation(eyeHeight: 2), timestamp: Double(index) * 0.1) == .collecting(.lookAtCamera))
        }
        tracker = FaceLivenessTracker(direction: .right)
        _ = tracker.consume(livenessObservation(), timestamp: 0)
        _ = tracker.consume(livenessObservation(), timestamp: 0.12)
        _ = tracker.consume(livenessObservation(), timestamp: 0.24)
        var wink = livenessObservation()
        wink.geometry.leftEyeOpenness *= 0.4
        #expect(tracker.consume(wink, timestamp: 0.4) == .collecting(.blink))
        #expect(tracker.consume(livenessObservation(), timestamp: 0.56) == .collecting(.blink))
    }

    @Test
    func qualityInvalidCuesAndAdditionalFacesClearProgress() {
        var poor = livenessObservation(); poor.quality = 0.1
        var excessiveQuality = livenessObservation(); excessiveQuality.quality = 2
        var invalid = livenessObservation(); invalid.geometry.leftEyeOpenness = .nan
        var multiple = livenessObservation(); multiple.faceCount = 2
        var missingGlare = livenessObservation(); missingGlare.glare = .unavailable
        var badYaw = livenessObservation(); badYaw.yaw = .nan
        for frame in [poor, excessiveQuality, invalid, multiple, missingGlare, badYaw] {
            var tracker = FaceLivenessTracker(direction: .right)
            blinkingSequence(&tracker)
            #expect(tracker.consume(frame, timestamp: 0.7) != .passed)
            let turn = livenessObservation(yaw: 22 * tracker.direction.sign, noseShift: 7 * tracker.direction.sign)
            #expect(tracker.consume(turn, timestamp: 0.85) == .collecting(.lookAtCamera))
        }
    }

    @Test
    func aCompletedChallengeAllowsEnrollmentTiltsWithoutSuppressingDenial() {
        var tracker = FaceLivenessTracker(direction: .left)
        blinkingSequence(&tracker)
        #expect(turnAndReturn(&tracker) == .passed)
        var tilted = livenessObservation(yaw: 22 * tracker.direction.sign, noseShift: 7 * tracker.direction.sign)
        tilted.pitch = 28
        #expect(tracker.consume(tilted, timestamp: 1.5) == .passed)
        tilted.enclosingDevice = true
        #expect(tracker.consume(tilted, timestamp: 1.6) == .rejected(.deviceOutline))
    }

    @Test
    func denialOverridesEvenACompletedChallengeAndRemainsLatched() {
        var tracker = FaceLivenessTracker(direction: .right)
        blinkingSequence(&tracker)
        #expect(turnAndReturn(&tracker) == .passed)
        var reflected = livenessObservation()
        reflected.glare = FaceGlareMeasurement(brightFraction: 0.2, largestBrightRegionFraction: 0.1, nativeCropWidth: 180)
        reflected.quality = 0
        #expect(reflected.denial == .reflection)
        #expect(tracker.consume(reflected, timestamp: 1.5) == .rejected(.reflection))
        #expect(tracker.consume(livenessObservation(), timestamp: 1.6) == .rejected(.reflection))
        var device = livenessObservation(); device.enclosingDevice = true; device.geometry = .unavailable
        tracker = FaceLivenessTracker(direction: .right)
        #expect(device.denial == .deviceOutline)
        #expect(tracker.consume(device, timestamp: 0) == .rejected(.deviceOutline))
    }
}

struct FaceCheckLivenessImageTests {
    @Test
    func aLargeConnectedNeutralReflectionIsDifferentFromSmallHighlights() throws {
        func image(scattered: Bool) -> [UInt8] {
            var rgba = [UInt8](repeating: 100, count: 100 * 100 * 4)
            for y in 0..<100 {
                for x in 0..<100 {
                    let isBright = scattered ? (x % 3 == 0 && y % 3 == 0) : (x >= 20 && x < 60 && y >= 20 && y < 60)
                    if isBright { for channel in 0..<3 { rgba[(y * 100 + x) * 4 + channel] = 250 } }
                    rgba[(y * 100 + x) * 4 + 3] = 255
                }
            }
            return rgba
        }
        let large = try #require(FaceLivenessImageCues.glare(rgba: image(scattered: false), width: 100, height: 100, nativeCropWidth: 180))
        let scattered = try #require(FaceLivenessImageCues.glare(rgba: image(scattered: true), width: 100, height: 100, nativeCropWidth: 180))
        #expect(large.hasLargeReflection)
        #expect(scattered.brightFraction > 0.08)
        #expect(!scattered.hasLargeReflection)
        #expect(FaceLivenessImageCues.glare(rgba: [], width: 100, height: 100, nativeCropWidth: 180) == nil)
        #expect(!FaceGlareMeasurement(brightFraction: .nan, largestBrightRegionFraction: 0.2, nativeCropWidth: 180).isUsable)
    }

    @Test
    func glareOnlyUsesTheFaceCrop() throws {
        let width = 240, height = 240
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 60..<180 {
            for x in 60..<180 {
                for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = 120 }
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider,
                                        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let measurement = try #require(FaceLivenessImageCues.glare(in: image, faceBounds: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        #expect(measurement.isUsable)
        #expect(measurement.brightFraction == 0)
        #expect(!measurement.hasLargeReflection)
    }

    @Test
    func aDeviceMustEncloseTheFaceWithPlausibleDimensions() {
        let face = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25)
        let device = [CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.1),
                      CGPoint(x: 0.7, y: 0.9), CGPoint(x: 0.3, y: 0.9)]
        #expect(FaceLivenessImageCues.deviceSurroundsFace(face, corners: device, confidence: 0.9))
        #expect(!FaceLivenessImageCues.deviceSurroundsFace(face.offsetBy(dx: 0.3, dy: 0), corners: device, confidence: 0.9))
        #expect(!FaceLivenessImageCues.deviceSurroundsFace(face, corners: device, confidence: 0.5))
        let background = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        #expect(!FaceLivenessImageCues.deviceSurroundsFace(face, corners: background, confidence: 0.95))
        let skewed = [CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.4),
                      CGPoint(x: 0.7, y: 0.9), CGPoint(x: 0.3, y: 0.6)]
        #expect(!FaceLivenessImageCues.deviceSurroundsFace(face, corners: skewed, confidence: 0.95))
    }
}
