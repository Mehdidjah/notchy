import CoreGraphics
import Foundation

/// Measurements from a camera frame, with no Vision objects or camera ownership.
struct FaceLivenessObservation: Equatable, Sendable {
    var geometry: FaceLivenessGeometry
    var yaw: Double
    var pitch: Double
    var quality: Double
    var glare: FaceGlareMeasurement
    var enclosingDevice: Bool
    var faceCount: Int = 1

    var denial: FaceLivenessFailure? {
        if enclosingDevice { return .deviceOutline }
        if glare.hasLargeReflection { return .reflection }
        return nil
    }
}

struct FaceLivenessGeometry: Equatable, Sendable {
    var leftEyeOpenness: Double
    var rightEyeOpenness: Double
    var interocularPixels: Double
    /// Eye corners and mouth extremities, measured in eye-distance units with roll removed.
    var planePoints: [CGPoint]
    /// Nose outline centre and tip; these are never used to fit the reference plane.
    var nosePoints: [CGPoint]

    static let unavailable = Self(leftEyeOpenness: 0, rightEyeOpenness: 0, interocularPixels: 0,
                                  planePoints: [], nosePoints: [])

    var noseOffset: Double {
        nosePoints.reduce(0) { $0 + Double($1.x) } / Double(max(nosePoints.count, 1))
    }

    var isUsable: Bool {
        leftEyeOpenness.isFinite && rightEyeOpenness.isFinite &&
        (0...0.8).contains(leftEyeOpenness) && (0...0.8).contains(rightEyeOpenness) &&
        interocularPixels.isFinite && interocularPixels >= 40 &&
        planePoints.count == 8 && nosePoints.count == 2 &&
        (planePoints + nosePoints).allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    static func measure(_ landmarks: FaceLandmarkPoints) -> Self? {
        let regions = [landmarks.leftEye, landmarks.rightEye, landmarks.nose,
                       landmarks.noseCrest, landmarks.outerLips]
        guard landmarks.leftEye.count >= 6, landmarks.rightEye.count >= 6,
              landmarks.nose.count >= 3, landmarks.noseCrest.count >= 2,
              landmarks.outerLips.count >= 6,
              regions.joined().allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        func mean(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.reduce(0) { $0 + $1.x } / Double(points.count),
                    y: points.reduce(0) { $0 + $1.y } / Double(points.count))
        }
        let eyes = [landmarks.leftEye, landmarks.rightEye].sorted { mean($0).x < mean($1).x }
        let a = mean(eyes[0]), b = mean(eyes[1])
        let distance = hypot(b.x - a.x, b.y - a.y)
        guard distance >= 40, distance.isFinite else { return nil }
        let dx = (b.x - a.x) / distance, dy = (b.y - a.y) / distance
        let centre = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        func normalize(_ point: CGPoint) -> CGPoint {
            let x = point.x - centre.x, y = point.y - centre.y
            return CGPoint(x: (x * dx + y * dy) / distance,
                           y: (-x * dy + y * dx) / distance)
        }
        let normalizedEyes = eyes.map { $0.map(normalize) }
        let mouth = landmarks.outerLips.map(normalize)
        func extremities(_ points: [CGPoint]) -> [CGPoint] {
            [points.min(by: { $0.x < $1.x })!, points.max(by: { $0.x < $1.x })!]
        }
        func openness(_ eye: [CGPoint]) -> Double? {
            let width = eye.map(\.x).max()! - eye.map(\.x).min()!
            let height = eye.map(\.y).max()! - eye.map(\.y).min()!
            guard width > 0.08 else { return nil }
            return Double(height / width)
        }
        guard let left = openness(normalizedEyes[0]), let right = openness(normalizedEyes[1]) else { return nil }
        let top = mouth.map(\.y).min()!, bottom = mouth.map(\.y).max()!
        let edgeBand = max(0.000001, (bottom - top) * 0.1)
        let upperMouth = mean(mouth.filter { $0.y <= top + edgeBand })
        let lowerMouth = mean(mouth.filter { $0.y >= bottom - edgeBand })
        let anchors = normalizedEyes.flatMap(extremities) + extremities(mouth) + [upperMouth, lowerMouth]
        let nose = landmarks.nose.map(normalize)
        let tip = landmarks.noseCrest.map(normalize).max(by: { $0.y < $1.y })!
        let geometry = Self(leftEyeOpenness: left, rightEyeOpenness: right,
                            interocularPixels: distance, planePoints: anchors,
                            nosePoints: [mean(nose), tip])
        return geometry.isUsable ? geometry : nil
    }

    /// Signed nose displacement left over after fitting a projective plane to eyes and mouth.
    /// A translated, rotated, stretched or perspective-warped flat picture has zero residual.
    /// This is a heuristic from RGB landmarks, not a depth sensor or a biometric guarantee.
    static func nonPlanarNoseMotion(from reference: Self, to current: Self) -> Double? {
        guard reference.isUsable, current.isUsable,
              let transform = FacePlaneTransform.fit(reference.planePoints, to: current.planePoints) else { return nil }
        let anchorErrors = zip(reference.planePoints, current.planePoints).compactMap { source, destination -> Double? in
            guard let predicted = transform.apply(source) else { return nil }
            return hypot(predicted.x - destination.x, predicted.y - destination.y)
        }
        guard anchorErrors.count == reference.planePoints.count else { return nil }
        let anchorError = sqrt(anchorErrors.reduce(0) { $0 + $1 * $1 } / Double(anchorErrors.count))
        guard anchorError <= 0.035 else { return nil }
        var residuals: [CGPoint] = []
        for (source, destination) in zip(reference.nosePoints, current.nosePoints) {
            guard let predicted = transform.apply(source) else { return nil }
            residuals.append(CGPoint(x: destination.x - predicted.x, y: destination.y - predicted.y))
        }
        let x = residuals.reduce(0) { $0 + $1.x } / Double(residuals.count)
        let y = residuals.reduce(0) { $0 + $1.y } / Double(residuals.count)
        let averageMagnitude = residuals.reduce(0) { $0 + hypot($1.x, $1.y) } / Double(residuals.count)
        guard averageMagnitude.isFinite else { return nil }
        // Inconsistent residuals are landmark noise. Do not turn that noise into evidence of depth.
        guard averageMagnitude > 0.0001 else { return 0 }
        let coherence = hypot(x, y) / averageMagnitude
        guard coherence >= 0.75, abs(x) >= max(0.035, anchorError * 3) else { return 0 }
        return x
    }
}

private struct FacePlaneTransform {
    let coefficients: [Double]

    func apply(_ point: CGPoint) -> CGPoint? {
        let h = coefficients, x = Double(point.x), y = Double(point.y)
        let divisor = h[6] * x + h[7] * y + 1
        guard divisor.isFinite, abs(divisor) > 0.000001 else { return nil }
        let result = CGPoint(x: (h[0] * x + h[1] * y + h[2]) / divisor,
                             y: (h[3] * x + h[4] * y + h[5]) / divisor)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }

    static func fit(_ source: [CGPoint], to destination: [CGPoint]) -> Self? {
        guard source.count == destination.count, source.count >= 4 else { return nil }
        var normal = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for (from, to) in zip(source, destination) {
            let x = Double(from.x), y = Double(from.y), u = Double(to.x), v = Double(to.y)
            let rows = [([x, y, 1, 0, 0, 0, -u * x, -u * y], u),
                        ([0, 0, 0, x, y, 1, -v * x, -v * y], v)]
            for (row, answer) in rows {
                for i in 0..<8 {
                    for j in 0..<8 { normal[i][j] += row[i] * row[j] }
                    normal[i][8] += row[i] * answer
                }
            }
        }
        for column in 0..<8 {
            let pivot = (column..<8).max { abs(normal[$0][column]) < abs(normal[$1][column]) }!
            guard abs(normal[pivot][column]) > 1e-10 else { return nil }
            normal.swapAt(column, pivot)
            let scale = normal[column][column]
            for j in column...8 { normal[column][j] /= scale }
            for row in 0..<8 where row != column {
                let multiplier = normal[row][column]
                for j in column...8 { normal[row][j] -= multiplier * normal[column][j] }
            }
        }
        let solution = normal.map { $0[8] }
        return solution.allSatisfy(\.isFinite) ? Self(coefficients: solution) : nil
    }
}

struct FaceGlareMeasurement: Equatable, Sendable {
    var brightFraction: Double
    var largestBrightRegionFraction: Double
    var nativeCropWidth: Int

    static let unavailable = Self(brightFraction: 0, largestBrightRegionFraction: 0, nativeCropWidth: 0)

    var isUsable: Bool {
        nativeCropWidth >= 50 && brightFraction.isFinite && largestBrightRegionFraction.isFinite &&
        (0...1).contains(brightFraction) && (0...brightFraction).contains(largestBrightRegionFraction)
    }
    var hasLargeReflection: Bool {
        isUsable && brightFraction >= 0.08 && largestBrightRegionFraction >= 0.06
    }
}

enum FaceLivenessImageCues {
    /// Looks only inside the detected face, so a bright window elsewhere cannot reject a scan.
    static func glare(in frame: CGImage, faceBounds: CGRect) -> FaceGlareMeasurement? {
        guard faceBounds.minX.isFinite, faceBounds.minY.isFinite,
              faceBounds.width.isFinite, faceBounds.height.isFinite,
              faceBounds.width > 0, faceBounds.height > 0 else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let bounds = CGRect(x: faceBounds.minX * Double(frame.width), y: faceBounds.minY * Double(frame.height),
                            width: faceBounds.width * Double(frame.width), height: faceBounds.height * Double(frame.height))
        let interior = bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.06).intersection(imageBounds).integral
        guard interior.width >= 50, interior.height >= 50, let crop = frame.cropping(to: interior) else { return nil }
        let scale = min(1, 128 / max(interior.width, interior.height))
        let width = max(1, Int(interior.width * scale)), height = max(1, Int(interior.height * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        return glare(rgba: bytes, width: width, height: height, nativeCropWidth: crop.width)
    }

    /// Connected bright neutral pixels distinguish a broad reflection from scattered skin shine.
    static func glare(rgba: [UInt8], width: Int, height: Int, nativeCropWidth: Int) -> FaceGlareMeasurement? {
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              rgba.count == width * height * 4 else { return nil }
        var bright = [Bool](repeating: false, count: width * height)
        for index in bright.indices {
            let colors = [rgba[index * 4], rgba[index * 4 + 1], rgba[index * 4 + 2]]
            let low = colors.min()!, high = colors.max()!
            bright[index] = low >= 235 && Int(high) - Int(low) <= 18
        }
        let brightCount = bright.filter { $0 }.count
        var largest = 0
        for index in bright.indices where bright[index] {
            var pending = [index], cursor = 0
            bright[index] = false
            while cursor < pending.count {
                let pixel = pending[cursor], row = pixel / width, column = pixel % width
                cursor += 1
                var neighbors: [Int] = []
                if column > 0 { neighbors.append(pixel - 1) }
                if column + 1 < width { neighbors.append(pixel + 1) }
                if row > 0 { neighbors.append(pixel - width) }
                if row + 1 < height { neighbors.append(pixel + width) }
                for neighbor in neighbors where bright[neighbor] {
                    bright[neighbor] = false
                    pending.append(neighbor)
                }
            }
            largest = max(largest, pending.count)
        }
        return FaceGlareMeasurement(brightFraction: Double(brightCount) / Double(width * height),
                                    largestBrightRegionFraction: Double(largest) / Double(width * height),
                                    nativeCropWidth: nativeCropWidth)
    }

    /// Rectangle and face use normalized top-left coordinates. A partial background edge is insufficient.
    static func deviceSurroundsFace(_ face: CGRect, corners: [CGPoint], confidence: Double, imageAspect: Double = 1) -> Bool {
        guard confidence.isFinite, confidence >= 0.8, corners.count == 4,
              corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              imageAspect.isFinite, imageAspect > 0, face.width > 0, face.height > 0 else { return false }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let area = box.width * box.height, faceArea = face.width * face.height
        guard area > 0, area < 0.92, min(box.width, box.height) >= 0.15,
              box.width > face.width * 1.18, box.height > face.height * 1.18,
              (0.08...0.68).contains(faceArea / area) else { return false }
        let ratio = min(box.width * imageAspect, box.height) / max(box.width * imageAspect, box.height)
        guard (0.32...0.95).contains(ratio) else { return false }
        let probes = [CGPoint(x: face.minX, y: face.minY), CGPoint(x: face.maxX, y: face.minY),
                      CGPoint(x: face.maxX, y: face.maxY), CGPoint(x: face.minX, y: face.maxY)]
        return probes.allSatisfy { point in
            let crosses = (0..<4).map { index -> Double in
                let a = corners[index], b = corners[(index + 1) % 4]
                return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            }
            return crosses.allSatisfy { $0 >= 0 } || crosses.allSatisfy { $0 <= 0 }
        }
    }
}

enum FaceLivenessDirection: CaseIterable, Equatable, Sendable {
    case left, right
    // Analysis uses unmirrored camera coordinates: turning toward the person's left moves
    // the nose toward positive image x and gives positive yaw. The mirrored preview reverses
    // its displayed x direction, so the spoken direction remains the person's own left/right.
    var sign: Double { self == .left ? 1 : -1 }
}

enum FaceLivenessPrompt: Equatable, Sendable {
    case lookAtCamera, blink, turn(FaceLivenessDirection), lookBackAtCamera, improveLighting, moveCloser, oneFace
    var message: String {
        switch self {
        case .lookAtCamera: "Look at the camera"
        case .blink: "Blink once"
        case .turn(.left): "Turn your head left slightly"
        case .turn(.right): "Turn your head right slightly"
        case .lookBackAtCamera: "Look back at the camera"
        case .improveLighting: "Use even lighting on your face"
        case .moveCloser: "Move closer to the camera"
        case .oneFace: "Keep only your face in view"
        }
    }
}

enum FaceLivenessFailure: Equatable, Sendable {
    case reflection, deviceOutline, invalidTiming
    var message: String {
        switch self {
        case .reflection: "A large reflection covers your face. Adjust the lighting and retry."
        case .deviceOutline: "A screen-shaped outline surrounds your face. Remove it and retry."
        case .invalidTiming: "The camera frames were interrupted. Please retry."
        }
    }
}

enum FaceLivenessResult: Equatable, Sendable {
    case collecting(FaceLivenessPrompt)
    case passed
    case rejected(FaceLivenessFailure)
}

/// A fresh active challenge for every check. Matching identity and enforcing the overall deadline
/// belong to the caller; missing frames must still be delivered here to break evidence continuity.
struct FaceLivenessTracker: Sendable {
    let direction: FaceLivenessDirection
    private enum Stage: Sendable { case baseline, blink, closed, turn, returning, passed }
    private var stage: Stage = .baseline
    private var baseline: FaceLivenessObservation?
    private var lastTimestamp: TimeInterval?
    private var stageStarted: TimeInterval?
    private var holdStarted: TimeInterval?
    private var holdFrames = 0
    private var rejection: FaceLivenessFailure?

    init(direction: FaceLivenessDirection) { self.direction = direction }

    mutating func consume(_ observation: FaceLivenessObservation?, timestamp: TimeInterval) -> FaceLivenessResult {
        if let rejection { return .rejected(rejection) }
        guard timestamp.isFinite, lastTimestamp.map({ timestamp > $0 }) ?? true else {
            rejection = .invalidTiming
            return .rejected(.invalidTiming)
        }
        if let lastTimestamp, timestamp - lastTimestamp > 1 { clearEvidence() }
        lastTimestamp = timestamp
        guard let frame = observation else {
            clearEvidence()
            return .collecting(.lookAtCamera)
        }
        // Denial always runs before quality and geometry gates, including after apparent success.
        if frame.enclosingDevice { rejection = .deviceOutline; return .rejected(.deviceOutline) }
        if frame.glare.hasLargeReflection { rejection = .reflection; return .rejected(.reflection) }
        guard frame.faceCount == 1 else { clearEvidence(); return .collecting(.oneFace) }
        guard frame.quality.isFinite, (0.3...1).contains(frame.quality), frame.glare.isUsable else {
            clearEvidence(); return .collecting(.improveLighting)
        }
        let yawLimit = stage == .passed ? 45.0 : 40.0
        let pitchLimit = stage == .passed ? 35.0 : 18.0
        guard frame.geometry.isUsable, frame.yaw.isFinite, frame.pitch.isFinite,
              abs(frame.yaw) <= yawLimit, abs(frame.pitch) <= pitchLimit else {
            clearEvidence(); return .collecting(.moveCloser)
        }
        let eyes = frame.geometry
        switch stage {
        case .baseline:
            guard abs(frame.yaw) <= 7, abs(frame.pitch) <= 12,
                  eyes.leftEyeOpenness >= 0.16, eyes.rightEyeOpenness >= 0.16 else {
                clearEvidence(); return .collecting(.lookAtCamera)
            }
            if let baseline, abs(eyes.noseOffset - baseline.geometry.noseOffset) > 0.025 {
                clearEvidence()
            }
            if baseline == nil { baseline = frame }
            if held(at: timestamp, frames: 3, duration: 0.2) {
                advance(to: .blink, at: timestamp)
                return .collecting(.blink)
            }
            return .collecting(.lookAtCamera)
        case .blink:
            guard let baseline else { clearEvidence(); return .collecting(.lookAtCamera) }
            guard abs(frame.yaw) <= 9 else { clearEvidence(); return .collecting(.lookAtCamera) }
            let ratios = eyeRatios(eyes, baseline.geometry)
            if ratios.0 <= 0.58, ratios.1 <= 0.58 {
                advance(to: .closed, at: timestamp)
            }
            return .collecting(.blink)
        case .closed:
            guard let baseline, let stageStarted, abs(frame.yaw) <= 9,
                  timestamp - stageStarted <= 0.9 else { clearEvidence(); return .collecting(.lookAtCamera) }
            let ratios = eyeRatios(eyes, baseline.geometry)
            if ratios.0 >= 0.82, ratios.1 >= 0.82, timestamp - stageStarted >= 0.045 {
                advance(to: .turn, at: timestamp)
                return .collecting(.turn(direction))
            }
            return .collecting(.blink)
        case .turn:
            guard let baseline else { clearEvidence(); return .collecting(.lookAtCamera) }
            let offset = (eyes.noseOffset - baseline.geometry.noseOffset) * direction.sign
            let residual = FaceLivenessGeometry.nonPlanarNoseMotion(from: baseline.geometry, to: eyes)
            let credibleTurn = frame.yaw * direction.sign >= 15 && frame.yaw * direction.sign <= 35 &&
                offset >= 0.045 && (residual.map { $0 * direction.sign >= 0.035 } ?? false)
            if credibleTurn {
                if held(at: timestamp, frames: 3, duration: 0.22) {
                    advance(to: .returning, at: timestamp)
                    return .collecting(.lookBackAtCamera)
                }
            } else { resetHold() }
            return .collecting(.turn(direction))
        case .returning:
            guard let baseline else { clearEvidence(); return .collecting(.lookAtCamera) }
            let ratios = eyeRatios(eyes, baseline.geometry)
            let centered = abs(frame.yaw) <= 7 && abs(eyes.noseOffset - baseline.geometry.noseOffset) <= 0.03 &&
                ratios.0 >= 0.8 && ratios.1 >= 0.8
            if centered {
                if held(at: timestamp, frames: 2, duration: 0.12) {
                    advance(to: .passed, at: timestamp)
                    return .passed
                }
            } else { resetHold() }
            return .collecting(.lookBackAtCamera)
        case .passed:
            return .passed
        }
    }

    private func eyeRatios(_ current: FaceLivenessGeometry, _ baseline: FaceLivenessGeometry) -> (Double, Double) {
        (current.leftEyeOpenness / max(baseline.leftEyeOpenness, 0.001),
         current.rightEyeOpenness / max(baseline.rightEyeOpenness, 0.001))
    }

    private mutating func held(at time: TimeInterval, frames: Int, duration: TimeInterval) -> Bool {
        if holdStarted == nil { holdStarted = time }
        holdFrames += 1
        return holdFrames >= frames && time - (holdStarted ?? time) >= duration
    }

    private mutating func advance(to next: Stage, at time: TimeInterval) {
        stage = next; stageStarted = time; resetHold()
    }

    private mutating func resetHold() { holdFrames = 0; holdStarted = nil }

    private mutating func clearEvidence() {
        stage = .baseline; baseline = nil; stageStarted = nil; resetHold()
    }
}
