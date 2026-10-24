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
