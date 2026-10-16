import AppKit
import SwiftUI

/// Atoll's colour coding for battery levels: green while comfortable, through yellow, to red
/// as the battery empties. Smooth mode blends between them; discrete mode snaps.
enum BluetoothBatteryPalette {
    private static let green = (red: 0.2, green: 0.78, blue: 0.35)
    private static let yellow = (red: 0.93, green: 0.75, blue: 0.2)
    private static let red = (red: 0.95, green: 0.36, blue: 0.3)

    /// `level` is 0...1. Urgency is `1 - level`: under 0.6 green, under 0.85 yellow, else red.
    static func color(forLevel level: Double, smooth: Bool) -> Color {
        let urgency = 1 - min(max(level, 0), 1)
        if !smooth {
            switch urgency {
            case ..<0.6: return color(green)
            case ..<0.85: return color(yellow)
            default: return color(red)
            }
        }
        switch urgency {
        case ..<0.6: return color(green)
        case ..<0.85: return blend(green, yellow, (urgency - 0.6) / 0.25)
        default: return blend(yellow, red, (urgency - 0.85) / 0.15)
        }
    }

    private typealias RGB = (red: Double, green: Double, blue: Double)

    private static func blend(_ from: RGB, _ to: RGB, _ fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        return Color(
            red: from.red + (to.red - from.red) * t,
            green: from.green + (to.green - from.green) * t,
            blue: from.blue + (to.blue - from.blue) * t
        )
    }

    private static func color(_ rgb: RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Left wing: the device symbol in a 20 x 15 box (hierarchical, white, filled variant) and,
/// when enabled, the device name scrolling beside it in 13-pt medium.
///
/// As in Atoll, the name's clip box is as wide as the whole info column, so it runs past the
/// column's right edge and the island's black centre (drawn after this wing) cuts it off at
/// the same point Atoll's does.
struct BluetoothHUDLeadingWing: View {
    let device: BluetoothAudioDevice
    let showsName: Bool
    /// Atoll's info column width (64 / 132 pt, plus half the swipe).
    let infoWidth: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: device.kind.systemImage)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .frame(width: 20, height: 15, alignment: .center)
            if showsName {
                BluetoothMarqueeText(
                    text: device.name,
                    fontSize: 13,
                    weight: .medium,
                    minDuration: 0.2,
                    frameWidth: infoWidth
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name) connected")
    }
}

/// Right wing: the device battery as a ring or a bar, optionally with "NN%", trailing with a
/// 4-pt inset. Empty when the level is unknown.
struct BluetoothHUDTrailingWing: View {
    let presentation: BluetoothHUDPresentation
    @ObservedObject var settings: BluetoothSettings

    var body: some View {
        HStack {
            if presentation.showsBattery, let level = presentation.batteryLevel {
                let fraction = Double(level) / 100
                let color = settings.useColorCodedBatteryDisplay
                    ? BluetoothBatteryPalette.color(forLevel: fraction, smooth: settings.useSmoothColorGradient)
                    : .white
                HStack(spacing: indicatorSpacing) {
                    if settings.useCircularBatteryIndicator {
                        BluetoothCircularBatteryIndicator(fraction: fraction, color: color)
                    } else {
                        BluetoothLinearBatteryIndicator(fraction: fraction, color: color)
                    }
                    if settings.showBatteryPercentageText {
                        Text(verbatim: "\(level)%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery \(level) percent")
            }
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var indicatorSpacing: CGFloat {
        if settings.useCircularBatteryIndicator {
            return settings.showBatteryPercentageText ? 8 : 2
        }
        return settings.showBatteryPercentageText ? 6 : 4
    }
}

/// A 16-pt ring: a faint full track and the level drawn clockwise from the top.
struct BluetoothCircularBatteryIndicator: View {
    let fraction: Double
    let color: Color

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(clamped, 0.015))
                .rotation(.degrees(-90))
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        .frame(width: 16, height: 16)
        .animation(.smooth(duration: 0.18), value: clamped)
    }
}

/// A 54 x 6 capsule bar filled to the level.
struct BluetoothLinearBatteryIndicator: View {
    let fraction: Double
    let color: Color

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 54, height: 6)
            Capsule()
                .fill(color)
                .frame(width: 54 * clamped, height: 6)
        }
        .frame(width: 54, height: 6)
        .animation(.smooth(duration: 0.18), value: clamped)
    }
}

/// One line that scrolls when it does not fit (Atoll's `MarqueeText`): two copies 20 pt apart;
/// 0.1 s after appearing, and after a `minDuration` pause on each pass, the line glides left
/// by one copy plus the gap over (text width / 30) seconds, snaps back and repeats. Text that
/// fits stays still.
struct BluetoothMarqueeText: View {
    static let gap: CGFloat = 20
    /// Atoll divides the text width (not the travel) by this to get each pass's duration.
    static let speed: CGFloat = 30
    /// Atoll waits this long after a reset before starting the loop.
    static let startDelay: Duration = .milliseconds(100)

    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var offset: CGFloat = 0

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: Self.measuringWeight(weight))
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    private var scrolls: Bool { textWidth > frameWidth }

    var body: some View {
        HStack(spacing: Self.gap) {
            Text(verbatim: text)
            if scrolls {
                Text(verbatim: text)
            }
        }
        .font(.system(size: fontSize, weight: weight))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: fontSize * 1.3)
        .task(id: "\(text)|\(frameWidth)") { await scroll() }
        .accessibilityLabel(text)
    }

    /// The AppKit weight that measures like the SwiftUI one.
    private static func measuringWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private func scroll() async {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard scrolls else { return }
        let distance = textWidth + Self.gap
        let duration = Double(textWidth / Self.speed)
        try? await Task.sleep(for: Self.startDelay)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(minDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withTransaction(reset) { offset = 0 }
        }
    }
}
