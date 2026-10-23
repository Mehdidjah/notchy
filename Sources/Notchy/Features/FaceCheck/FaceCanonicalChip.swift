import CoreGraphics
import Foundation

/// Five anatomical anchors for the 112-pixel embedding profile, in unmirrored image coordinates.
/// The target coordinates follow the MIT-licensed InsightFace alignment convention; see model notices.
enum FaceCanonicalChip {
    // The reference target table is Float32 before the similarity fit promotes to Double.
    static let targets: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041)
    ].map { CGPoint(x: CGFloat(Float($0.x)), y: CGFloat(Float($0.y))) }

    static func anchors(_ landmarks: FaceLandmarkPoints) -> [CGPoint]? {
        let groups = [landmarks.leftEye, landmarks.rightEye, landmarks.noseCrest, landmarks.outerLips]
        guard groups.allSatisfy({ $0.count >= 2 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) else { return nil }
        func mean(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
                    y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count))
        }
        var left = mean(landmarks.leftEye), right = mean(landmarks.rightEye)
        let middle = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        let mouth = mean(landmarks.outerLips)
        let downHint = CGPoint(x: mouth.x - middle.x, y: mouth.y - middle.y)
        func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
        let acrossHint = CGPoint(x: downHint.y, y: -downHint.x)
        if dot(left, acrossHint) > dot(right, acrossHint) { swap(&left, &right) }
        let span = hypot(right.x - left.x, right.y - left.y)
        guard span >= 20 else { return nil }
        let across = CGPoint(x: (right.x - left.x) / span, y: (right.y - left.y) / span)
        let down = CGPoint(x: -across.y, y: across.x)
        guard dot(downHint, down) > span * 0.2,
              let tip = landmarks.noseCrest.max(by: { dot($0, down) < dot($1, down) }),
              let mouthLeft = landmarks.outerLips.min(by: { dot($0, across) < dot($1, across) }),
              let mouthRight = landmarks.outerLips.max(by: { dot($0, across) < dot($1, across) }),
              dot(tip, down) > dot(middle, down), dot(tip, down) < dot(mouth, down)
        else { return nil }
        return [left, right, tip, mouthLeft, mouthRight]
    }

    static func render(_ image: CGImage, landmarks: FaceLandmarkPoints) -> CGImage? {
        guard let points = anchors(landmarks), let transform = FaceSimilarityTransform.fit(from: points, to: targets) else { return nil }
        return render(image, imageToChip: transform)?.makeImage()
    }

    /// Pixel centres are integers. Match the pinned OpenCV 4.12 INTER_LINEAR reference:
    /// round row/column terms separately at 1/1024, then select the 1/32 interpolation cell.
    /// Rounding the complete coordinate directly to 1/32 changes some rotated face chips.
    static func render(_ image: CGImage, imageToChip: FaceSimilarityTransform) -> FaceChipPixels? {
        guard let inverse = imageToChip.inverse,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * image.height)
        let size = 112
        // Checking the extrema bounds every affine coordinate and the fixed-point terms
        // below. Reject pathological transforms before converting floating-point to Int.
        let corners = [CGPoint.zero, CGPoint(x: size - 1, y: 0),
                       CGPoint(x: 0, y: size - 1), CGPoint(x: size - 1, y: size - 1)]
        guard corners.map(inverse.apply).allSatisfy({
            $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e7 && abs($0.y) < 1e7
        }) else { return nil }
        let columnX = (0..<size).map { Int((inverse.a * Double($0) * 1024).rounded(.toNearestOrEven)) }
        let columnY = (0..<size).map { Int((inverse.b * Double($0) * 1024).rounded(.toNearestOrEven)) }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        func value(_ x: Int, _ y: Int, _ channel: Int) -> Int {
            guard x >= 0, y >= 0, x < image.width, y < image.height else { return 0 }
            return Int(pixels[y * context.bytesPerRow + x * 4 + channel])
        }
        for row in 0..<size {
            let rowX = Int(((-inverse.b * Double(row) + inverse.tx) * 1024).rounded(.toNearestOrEven)) + 16
            let rowY = Int(((inverse.a * Double(row) + inverse.ty) * 1024).rounded(.toNearestOrEven)) + 16
            for column in 0..<size {
                let x = (rowX + columnX[column]) >> 5
                let y = (rowY + columnY[column]) >> 5
                let left = x >> 5, top = y >> 5
                let fx = x & 31, fy = y & 31
                let offset = (row * size + column) * 4
                for channel in 0..<3 {
                    let upper = value(left, top, channel) * (32 - fx) + value(left + 1, top, channel) * fx
                    let lower = value(left, top + 1, channel) * (32 - fx) + value(left + 1, top + 1, channel) * fx
                    bytes[offset + channel] = UInt8((upper * (32 - fy) + lower * fy + 512) >> 10)
                }
                bytes[offset + 3] = 255
            }
        }
        return FaceChipPixels(size: size, bytes: bytes)
    }
}
