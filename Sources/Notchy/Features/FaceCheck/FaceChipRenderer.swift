import CoreGraphics
import Foundation

/// A rendered face chip: `size × size` pixels in rows from the top, four bytes per pixel in
/// red, green, blue, unused order, in sRGB.
///
/// Raw bytes rather than only a `CGImage` so the embedder can fill its model input without
/// decoding an image again, and so tests can read exact values.
struct FaceChipPixels: Equatable, Sendable {
    static let bytesPerPixel = 4

    let size: Int
    let bytes: [UInt8]

    func rgb(column: Int, row: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let index = (row * size + column) * Self.bytesPerPixel
        return (bytes[index], bytes[index + 1], bytes[index + 2])
    }

    /// The chip as an opaque RGB image.
    func makeImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * Self.bytesPerPixel,
            bytesPerRow: size * Self.bytesPerPixel,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// Cuts the face chip out of a camera frame exactly the way dlib's `extract_image_chip` does,
/// so the network sees the same pixels it was trained on. (The steps follow dlib's behaviour;
/// its licence notice is in `FaceChipTemplate.swift`.)
///
/// Why not just let Core Graphics draw the frame through the alignment transform: on the same
/// photos and landmarks, such a warp moved descriptors 0.03–0.075 (median) and up to 0.12 away
/// from those of dlib's own chips, whichever interpolation quality was asked for. That is a large
/// share of the 0.5–0.6 match limits and as much as the gap between two presets. This renderer
/// moves them by 0.
///
/// Core Graphics copies the part of the frame around the face into an sRGB buffer, one image
/// pixel per buffer pixel, which also converts the camera's colour space. Everything after that
/// is done in Swift, step for step as dlib does it, because each step changes the pixels the
/// network sees:
/// 1. **Region.** The chip's square, rotated into place, grown by a margin and rounded to whole
///    pixels, clipped to the frame.
/// 2. **Shrinking.** While the face is still more than the chip's size after halving, the region
///    is halved with dlib's 5 × 5 filter (weights 1 4 6 4 1, integer sums, truncated). dlib then
///    places the chip with its own nominal halving formula, which sits half a source pixel away
///    from where its filter actually centres; that offset is reproduced too.
/// 3. **Sampling.** Bilinear: four neighbours, black where a neighbour is outside, values
///    truncated to whole bytes.
///
/// Checked against dlib itself on real photos (82 faces): identical bytes for faces up to the
/// chip's size, and through one or two halvings as well. In an optimised build a chip from a
/// 720p or 1080p frame takes about 0.3 ms, rising to about 3 ms for a face filling the frame; it
/// belongs on the pipeline's background actor, never the main actor.
enum FaceChipRenderer {
    /// Cuts the chip `alignment` describes out of `image`. `nil` when the chip lies entirely
    /// outside the image or the drawing buffer cannot be made.
    static func render(_ image: CGImage, alignment: FaceChipAlignment) -> FaceChipPixels? {
        let size = alignment.chipSize
        guard size >= 2, image.width > 0, image.height > 0 else { return nil }

        let chipRect = DlibRect.chip(of: alignment)
        let angle = alignment.templateToImage.rotation
        let levels = pyramidLevels(chipSize: size, fitScale: alignment.fitScale)

        // 1. The region dlib reads: the rotated square plus a margin that grows with each halving.
        var margin = 2.0
        for _ in 0..<levels { margin = margin * 2 + 2 }
        let corners = chipRect.rotatedCorners(by: angle)
        let hull = DlibRect(
            left: corners.map(\.x).min() ?? 0,
            top: corners.map(\.y).min() ?? 0,
            right: corners.map(\.x).max() ?? 0,
            bottom: corners.map(\.y).max() ?? 0
        )
        let frame = DlibRect(left: 0, top: 0, right: Double(image.width - 1), bottom: Double(image.height - 1))
        let region = hull.grown(by: margin).intersection(frame).roundedToPixels()
        guard !region.isEmpty, var source = RGBPlane(copying: image, region: region) else { return nil }

        // 2. Halve as many times as dlib would, and follow the chip square down with it.
        var levelRect = chipRect.offset(x: -region.left, y: -region.top)
        for _ in 0..<levels {
            source = source.halvedLikeDlib()
            levelRect = levelRect.halvedLikeDlib()
        }

        // 3. Chip pixel (column, row) → `origin + column × across + row × down` in the level.
        let placed = levelRect.rotatedCorners(by: angle)
        let steps = Double(size - 1)
        let origin = placed[0]
        let across = (x: (placed[1].x - origin.x) / steps, y: (placed[1].y - origin.y) / steps)
        let down = (x: (placed[2].x - origin.x) / steps, y: (placed[2].y - origin.y) / steps)

        var bytes = [UInt8](repeating: 0, count: size * size * FaceChipPixels.bytesPerPixel)
        for row in 0..<size {
            for column in 0..<size {
                let output = (row * size + column) * FaceChipPixels.bytesPerPixel
                bytes[output + 3] = 255
                let x = origin.x + Double(column) * across.x + Double(row) * down.x
                let y = origin.y + Double(column) * across.y + Double(row) * down.y
                source.sampleBilinear(x: x, y: y, into: &bytes, at: output)
            }
        }
        return FaceChipPixels(size: size, bytes: bytes)
    }

    /// `render(_:alignment:)` as an opaque RGB `CGImage`.
    static func renderImage(_ image: CGImage, alignment: FaceChipAlignment) -> CGImage? {
        render(image, alignment: alignment)?.makeImage()
    }

    /// How many times dlib halves the frame before sampling: while the chip square, halved once
    /// more, would still cover more pixels than the chip has. dlib measures the square as one
    /// pixel narrower than `size × fitScale` but counts both edges, so halving starts just below a
    /// fit scale of 2.
    static func pyramidLevels(chipSize: Int = FaceChipTemplate.chipSize, fitScale: Double) -> Int {
        guard fitScale.isFinite, chipSize >= 2 else { return 0 }
        let size = Double(chipSize)
        var span = size * fitScale - 1
        var levels = 0
        while levels < maximumPyramidLevels {
            span /= 2
            guard span + 1 > size else { break }
            levels += 1
        }
        return levels
    }

    /// A face 256 times larger than the chip is far beyond any camera frame; the cap only keeps
    /// the loop bounded.
    private static let maximumPyramidLevels = 8
}

// MARK: - dlib's rectangles

/// A real-valued rectangle measured the way dlib measures them: `left...right` inclusive, so its
/// width is `right − left + 1`.
private struct DlibRect {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    var isEmpty: Bool { top > bottom || left > right }
    var centre: (x: Double, y: Double) { ((left + right) / 2, (top + bottom) / 2) }

    /// dlib's chip square for an alignment: centred where the fit puts the chip's centre, one
    /// pixel narrower than `size × fitScale`.
    static func chip(of alignment: FaceChipAlignment) -> DlibRect {
        let half = Double(alignment.chipSize) / 2
        let centre = alignment.templateToImage.apply(CGPoint(x: half, y: half))
        let span = (Double(alignment.chipSize) * alignment.fitScale - 1) / 2
        return DlibRect(
            left: Double(centre.x) - span,
            top: Double(centre.y) - span,
            right: Double(centre.x) + span,
            bottom: Double(centre.y) + span
        )
    }

    /// Top-left, top-right, bottom-left and bottom-right corners turned about the centre.
    func rotatedCorners(by angle: Double) -> [(x: Double, y: Double)] {
        let (cx, cy) = centre
        let cosine = cos(angle)
        let sine = sin(angle)
        return [(left, top), (right, top), (left, bottom), (right, bottom)].map { point in
            let dx = point.0 - cx
            let dy = point.1 - cy
            return (cx + cosine * dx - sine * dy, cy + sine * dx + cosine * dy)
        }
    }

    func grown(by amount: Double) -> DlibRect {
        DlibRect(left: left - amount, top: top - amount, right: right + amount, bottom: bottom + amount)
    }

    func intersection(_ other: DlibRect) -> DlibRect {
        DlibRect(
            left: max(left, other.left),
            top: max(top, other.top),
            right: min(right, other.right),
            bottom: min(bottom, other.bottom)
        )
    }

    /// dlib's conversion to an integer rectangle: each edge rounded half up.
    func roundedToPixels() -> DlibRect {
        DlibRect(
            left: (left + 0.5).rounded(.down),
            top: (top + 0.5).rounded(.down),
            right: (right + 0.5).rounded(.down),
            bottom: (bottom + 0.5).rounded(.down)
        )
    }

    func offset(x: Double, y: Double) -> DlibRect {
        DlibRect(left: left + x, top: top + y, right: right + x, bottom: bottom + y)
    }

    /// Where dlib says a rectangle lands after one halving of the image.
    func halvedLikeDlib() -> DlibRect {
        DlibRect(left: left / 2 - 1.25, top: top / 2 - 0.75, right: right / 2 - 1.25, bottom: bottom / 2 - 0.75)
    }
}

// MARK: - Pixels

/// Three bytes per pixel, rows from the top. Pixel centres sit on whole numbers here, as in dlib.
private struct RGBPlane {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Copies an integer region of `image` (inclusive edges) pixel for pixel through Core Graphics.
    init?(copying image: CGImage, region: DlibRect) {
        let width = Int(region.right - region.left) + 1
        let height = Int(region.bottom - region.top) + 1
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        // Core Graphics puts the origin at the bottom left: place the image so the region's top
        // row lands on the buffer's top row.
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(
            x: -region.left,
            y: Double(height) - Double(image.height) + region.top,
            width: Double(image.width),
            height: Double(image.height)
        ))
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let rgba = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var bytes = [UInt8](repeating: 0, count: width * height * 3)
        for row in 0..<height {
            for column in 0..<width {
                let from = row * rowBytes + column * 4
                let to = (row * width + column) * 3
                bytes[to] = rgba[from]
                bytes[to + 1] = rgba[from + 1]
                bytes[to + 2] = rgba[from + 2]
            }
        }
        self.init(width: width, height: height, bytes: bytes)
    }

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// dlib's halving: a 1 4 6 4 1 filter along each row and then each column, keeping every
    /// second sample, integer sums divided by 256 and truncated. Output pixel `(c, r)` is centred
    /// on input pixel `(2c + 2, 2r + 2)`.
    func halvedLikeDlib() -> RGBPlane {
        guard width > 8, height > 8 else { return RGBPlane(width: 0, height: 0, bytes: []) }
        let outWidth = (width - 3) / 2
        let outHeight = (height - 3) / 2

        var rows = [Int](repeating: 0, count: height * outWidth * 3)
        for row in 0..<height {
            for column in 0..<outWidth {
                let start = (row * width + 2 * column) * 3
                let to = (row * outWidth + column) * 3
                for channel in 0..<3 {
                    rows[to + channel] = Int(bytes[start + channel])
                        + 4 * Int(bytes[start + 3 + channel])
                        + 6 * Int(bytes[start + 6 + channel])
                        + 4 * Int(bytes[start + 9 + channel])
                        + Int(bytes[start + 12 + channel])
                }
            }
        }

        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let stride = outWidth * 3
        for outRow in 0..<outHeight {
            let centre = (2 * outRow + 2) * stride
            for index in 0..<stride {
                let sum = rows[centre - 2 * stride + index]
                    + 4 * rows[centre - stride + index]
                    + 6 * rows[centre + index]
                    + 4 * rows[centre + stride + index]
                    + rows[centre + 2 * stride + index]
                out[outRow * stride + index] = UInt8(sum / 256)
            }
        }
        return RGBPlane(width: outWidth, height: outHeight, bytes: out)
    }

    /// dlib's bilinear sample at `(x, y)`, written as RGB into `output` at `offset`. Leaves the
    /// output black when any of the four neighbours is outside the plane.
    func sampleBilinear(x: Double, y: Double, into output: inout [UInt8], at offset: Int) {
        let left = x.rounded(.down)
        let top = y.rounded(.down)
        guard left >= 0, top >= 0, left + 1 < Double(width), top + 1 < Double(height) else { return }
        let fractionX = x - left
        let fractionY = y - top
        let topLeft = (Int(top) * width + Int(left)) * 3
        let bottomLeft = topLeft + width * 3
        for channel in 0..<3 {
            let upper = (1 - fractionX) * Double(bytes[topLeft + channel])
                + fractionX * Double(bytes[topLeft + 3 + channel])
            let lower = (1 - fractionX) * Double(bytes[bottomLeft + channel])
                + fractionX * Double(bytes[bottomLeft + 3 + channel])
            let value = (1 - fractionY) * upper + fractionY * lower
            output[offset + channel] = UInt8(min(255, max(0, value)).rounded(.towardZero))
        }
    }
}
