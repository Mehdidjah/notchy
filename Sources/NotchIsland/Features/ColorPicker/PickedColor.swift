import AppKit
import SwiftUI

/// A colour sampled from the screen, stored as sRGB components so every text format derives
/// from the same numbers the swatch is drawn with.
struct PickedColor: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let pickedAt: Date

    init(
        id: UUID = UUID(),
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        pickedAt: Date = Date()
    ) {
        self.id = id
        self.red = Self.unitClamped(red)
        self.green = Self.unitClamped(green)
        self.blue = Self.unitClamped(blue)
        self.alpha = Self.unitClamped(alpha)
        self.pickedAt = pickedAt
    }

    /// Converts to sRGB first. The sampler can hand back Display P3 or device-grey colours whose
    /// raw components would not match what the user saw, and some pattern colours cannot be
    /// converted at all.
    init?(nsColor: NSColor, pickedAt: Date = Date()) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent,
            alpha: srgb.alphaComponent,
            pickedAt: pickedAt
        )
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var isOpaque: Bool { alpha >= 1 }

    /// The 8-bit channels every text format is built from.
    var channels: PickedColorChannels {
        PickedColorChannels(
            red: Self.byte(red),
            green: Self.byte(green),
            blue: Self.byte(blue),
            alpha: Self.byte(alpha)
        )
    }

    /// Two picks of the same on-screen colour, regardless of when they were taken.
    func looksLike(_ other: PickedColor) -> Bool {
        channels == other.channels
    }

    private static func unitClamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    /// Rounds instead of truncating so a channel that lands on 127.99999 reads back as 128.
    private static func byte(_ component: Double) -> Int {
        Int((component * 255).rounded())
    }
}

struct PickedColorChannels: Hashable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
}

/// The text representations the picker can copy.
enum PickedColorFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case hex
    case rgb
    case rgba
    case hsl
    case hsla
    case hsv
    case swiftUI
    case uiColor

    var id: Self { self }

    var displayName: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .rgba: "RGBA"
        case .hsl: "HSL"
        case .hsla: "HSLA"
        case .hsv: "HSV"
        case .swiftUI: "SwiftUI"
        case .uiColor: "UIColor"
        }
    }
}

// MARK: - Formatting

extension PickedColor {
    func formatted(as format: PickedColorFormat) -> String {
        switch format {
        case .hex: hexString
        case .rgb: rgbString
        case .rgba: rgbaString
        case .hsl: hslString
        case .hsla: hslaString
        case .hsv: hsvString
        case .swiftUI: swiftUIString
        case .uiColor: uiColorString
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the colour is translucent.
    var hexString: String {
        let c = channels
        var hex = "#" + Self.hexPair(c.red) + Self.hexPair(c.green) + Self.hexPair(c.blue)
        if !isOpaque { hex += Self.hexPair(c.alpha) }
        return hex
    }

    var rgbString: String {
        let c = channels
        return "rgb(\(c.red), \(c.green), \(c.blue))"
    }

    var rgbaString: String {
        let c = channels
        return "rgba(\(c.red), \(c.green), \(c.blue), \(Self.twoPlaces(alpha)))"
    }

    var hslString: String {
        let hsl = hsl
        return "hsl(\(Self.degrees(hsl.hue)), \(Self.percent(hsl.saturation)), \(Self.percent(hsl.lightness)))"
    }

    var hslaString: String {
        let hsl = hsl
        return "hsla(\(Self.degrees(hsl.hue)), \(Self.percent(hsl.saturation)), \(Self.percent(hsl.lightness)), \(Self.twoPlaces(alpha)))"
    }

    /// HSV is the same model as HSB; the label follows the CSS-style function name.
    var hsvString: String {
        let hsv = hsv
        return "hsv(\(Self.degrees(hsv.hue)), \(Self.percent(hsv.saturation)), \(Self.percent(hsv.value)))"
    }

    var swiftUIString: String {
        "Color(red: \(Self.threePlaces(red)), green: \(Self.threePlaces(green)), blue: \(Self.threePlaces(blue)), opacity: \(Self.threePlaces(alpha)))"
    }

    var uiColorString: String {
        "UIColor(red: \(Self.threePlaces(red)), green: \(Self.threePlaces(green)), blue: \(Self.threePlaces(blue)), alpha: \(Self.threePlaces(alpha)))"
    }

    /// Hue in degrees (0..<360), saturation and lightness in 0...1.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        return (hue(maximum: maximum, delta: delta), saturation, lightness)
    }

    /// Hue in degrees (0..<360), saturation and value in 0...1.
    var hsv: (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let saturation = maximum > 0 ? delta / maximum : 0
        guard delta > 0 else { return (0, saturation, maximum) }
        return (hue(maximum: maximum, delta: delta), saturation, maximum)
    }

    private func hue(maximum: Double, delta: Double) -> Double {
        let sector: Double
        if maximum == red {
            sector = (green - blue) / delta
        } else if maximum == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func hexPair(_ byte: Int) -> String {
        let hex = String(byte, radix: 16, uppercase: true)
        return hex.count == 1 ? "0" + hex : hex
    }

    private static func degrees(_ hue: Double) -> String {
        let rounded = Int(hue.rounded())
        return String(rounded == 360 ? 0 : rounded)
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // `String(format:)` without a locale always uses a dot, which these code snippets need.
    private static func twoPlaces(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func threePlaces(_ value: Double) -> String { String(format: "%.3f", value) }
}

// MARK: - Age

extension PickedColor {
    /// "Just now", "5m ago", "3h ago", "2d ago".
    func relativeAge(now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(pickedAt))
        if seconds < 60 { return "Just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}
