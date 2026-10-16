import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// An sRGB colour that can cross concurrency domains.
struct MediaRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = MediaRGB(red: 1, green: 1, blue: 1)
    static let gray = MediaRGB(red: 0.5, green: 0.5, blue: 0.5)
    /// SwiftUI's `Color.gray` (system grey), which tints the spectrum when
    /// "Colored spectrogram" is off.
    static let systemGray = MediaRGB(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0)

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor.white
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        self.init(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    /// Relative luminance with Rec. 709 weights.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Scales the channels so the luminance reaches
    /// `factor` (clamped per channel), so dark artwork still yields a readable tint.
    func ensuringMinimumBrightness(_ factor: Double) -> MediaRGB {
        guard factor >= 0, factor <= 1 else { return self }
        let lum = luminance
        guard lum > 0 else { return MediaRGB(red: factor, green: factor, blue: factor) }
        let scale = factor / lum
        return MediaRGB(red: min(red * scale, 1), green: min(green * scale, 1), blue: min(blue * scale, 1))
    }

    /// The same hue turned half way round the wheel.
    var opposing: MediaRGB {
        let (h, s, b) = hsb
        return MediaRGB(hue: (h + 0.5).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b)
    }
}

/// The artwork and everything derived from it, computed off the main thread.
struct MediaArtworkAnalysis: @unchecked Sendable {
    let image: NSImage
    let glow: NSImage
    let quickColor: MediaRGB
    let primary: MediaRGB
    let secondary: MediaRGB
    let isWide: Bool
}

enum MediaArtworkProcessing {
    /// Decodes and analyses artwork bytes. Safe to call from any thread.
    static func analyze(data: Data, mode: MediaColorExtractionMode) -> MediaArtworkAnalysis? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            guard let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            return analyze(cgImage: cgImage, mode: mode)
        }
        return analyze(cgImage: cgImage, mode: mode)
    }

    static func analyze(cgImage: CGImage, mode: MediaColorExtractionMode) -> MediaArtworkAnalysis {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)
        let quick = quickAverageColor(cgImage)
        let (primary, secondary) = prominentColors(cgImage, mode: mode)
        let glow = blurredTexture(cgImage, radius: 40).map { NSImage(cgImage: $0, size: size) } ?? image
        return MediaArtworkAnalysis(
            image: image,
            glow: glow,
            quickColor: quick,
            primary: primary,
            secondary: secondary,
            isWide: size.height > 0 && size.width / size.height > 1
        )
    }

    // MARK: - Colours

    /// Cheap 32-px average used to tint the UI before the full extraction lands. Near black
    /// becomes 50 % grey; anything darker than 0.5 brightness is lifted to 0.5 while
    /// keeping the hue.
    static func quickAverageColor(_ cgImage: CGImage) -> MediaRGB {
        guard let pixels = rgbaPixels(cgImage, side: 32) else { return .gray }
        var r = 0.0, g = 0.0, b = 0.0
        for pixel in pixels {
            r += pixel.r
            g += pixel.g
            b += pixel.b
        }
        let count = Double(max(pixels.count, 1))
        return liftedAverage(MediaRGB(red: r / count, green: g / count, blue: b / count))
    }

    static func liftedAverage(_ average: MediaRGB) -> MediaRGB {
        let minBrightness = 0.5
        if average.red < 0.03, average.green < 0.03, average.blue < 0.03 {
            return MediaRGB(red: minBrightness, green: minBrightness, blue: minBrightness)
        }
        let (h, s, b) = average.hsb
        guard b < minBrightness else { return average }
        return MediaRGB(hue: h, saturation: s * (b / minBrightness), brightness: minBrightness)
    }

    /// Primary and secondary colours of the artwork.
    ///
    /// Vibrant: pixels are bucketed into 16 hue bins weighted by saturation² × brightness,
    /// ignoring near-greys, near-blacks and near-whites; the heaviest bin is the primary,
    /// the heaviest bin at least 60° away the secondary (else the complementary hue).
    /// Legacy: the lifted average and its complementary hue.
    static func prominentColors(_ cgImage: CGImage, mode: MediaColorExtractionMode) -> (MediaRGB, MediaRGB) {
        guard let pixels = rgbaPixels(cgImage, side: 64) else { return (.gray, .gray) }

        if mode == .legacy {
            var r = 0.0, g = 0.0, b = 0.0
            for pixel in pixels {
                r += pixel.r
                g += pixel.g
                b += pixel.b
            }
            let count = Double(max(pixels.count, 1))
            let primary = liftedAverage(MediaRGB(red: r / count, green: g / count, blue: b / count))
            return (primary, primary.opposing)
        }

        let bucketCount = 16
        var buckets = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, weight: 0.0), count: bucketCount)
        for pixel in pixels {
            let (h, s, br) = hsb(r: pixel.r, g: pixel.g, b: pixel.b)
            if br < 0.10 || br > 0.95 || s < 0.20 { continue }
            let weight = s * s * br
            let index = min(Int(h * Double(bucketCount)), bucketCount - 1)
            buckets[index].r += pixel.r * weight
            buckets[index].g += pixel.g * weight
            buckets[index].b += pixel.b * weight
            buckets[index].weight += weight
        }

        guard let primaryIndex = buckets.indices.max(by: { buckets[$0].weight < buckets[$1].weight }),
              buckets[primaryIndex].weight > 0
        else { return (.gray, .gray) }

        func enhanced(_ index: Int) -> MediaRGB {
            let bucket = buckets[index]
            let raw = MediaRGB(red: bucket.r / bucket.weight, green: bucket.g / bucket.weight, blue: bucket.b / bucket.weight)
            let (h, s, b) = raw.hsb
            return MediaRGB(hue: h, saturation: min(1, s * 1.2), brightness: min(1, b * 1.1))
        }

        let primary = enhanced(primaryIndex)
        var secondaryIndex: Int?
        var bestWeight = 0.0
        for index in buckets.indices where index != primaryIndex && buckets[index].weight > 0 {
            let difference = Double(abs(index - primaryIndex)) / Double(bucketCount)
            let wrapped = min(difference, 1 - difference) * 360
            if wrapped >= 60, buckets[index].weight > bestWeight {
                bestWeight = buckets[index].weight
                secondaryIndex = index
            }
        }
        let secondary = secondaryIndex.map(enhanced) ?? primary.opposing
        return (primary, secondary)
    }

    // MARK: - Glow

    /// A Gaussian-blurred copy for the glow behind the open artwork. The image is first
    /// scaled to 600 px so the 40-px radius reads the same for any source resolution, and
    /// the edges are left to fade instead of being clamped.
    static func blurredTexture(_ cgImage: CGImage, radius: Double) -> CGImage? {
        var input = CIImage(cgImage: cgImage)
        let longest = Double(max(cgImage.width, cgImage.height))
        if longest > 600 {
            let scale = 600 / longest
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input
        filter.radius = Float(radius)
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    // MARK: - Pixels

    private struct Pixel {
        var r: Double
        var g: Double
        var b: Double
    }

    private static func rgbaPixels(_ cgImage: CGImage, side: Int) -> [Pixel]? {
        let scale = min(Double(side) / Double(max(cgImage.width, 1)), Double(side) / Double(max(cgImage.height, 1)))
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            pixels.append(Pixel(r: Double(bytes[index]) / 255, g: Double(bytes[index + 1]) / 255, b: Double(bytes[index + 2]) / 255))
        }
        return pixels
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }
}

extension MediaRGB {
    /// Top-to-bottom gradient for the spectrum: the colour into its opposing hue (vibrant)
    /// or SwiftUI's own gradient of the colour (legacy).
    func spectrogramStyle(mode: MediaColorExtractionMode, secondary: MediaRGB? = nil) -> AnyShapeStyle {
        switch mode {
        case .legacy:
            return AnyShapeStyle(color.gradient)
        case .vibrant:
            return AnyShapeStyle(LinearGradient(
                colors: [color, (secondary ?? opposing).color],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }
}
