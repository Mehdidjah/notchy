import AppKit
import SwiftUI

/// Colour-coded palette: green while comfortable, yellow from 60 %, red from 85 %.
enum SystemHUDPalette {
    typealias Components = (red: Double, green: Double, blue: Double)

    static let green: Components = (0.2, 0.78, 0.35)
    static let yellow: Components = (0.93, 0.75, 0.2)
    static let red: Components = (0.95, 0.36, 0.3)

    static let yellowThreshold: Double = 0.6
    static let redThreshold: Double = 0.85

    /// Snaps to green, yellow or red.
    static func discreteComponents(for intensity: Double) -> Components {
        let clamped = min(max(intensity, 0), 1)
        if clamped < yellowThreshold { return green }
        if clamped < redThreshold { return yellow }
        return red
    }

    /// Stays green to 60 %, blends to yellow by 85 %, then to red by 100 %.
    static func smoothComponents(for intensity: Double) -> Components {
        let clamped = min(max(intensity, 0), 1)
        if clamped < yellowThreshold { return green }
        if clamped < redThreshold {
            return blend(green, yellow, (clamped - yellowThreshold) / (redThreshold - yellowThreshold))
        }
        return blend(yellow, red, (clamped - redThreshold) / (1 - redThreshold))
    }

    static func color(_ components: Components) -> Color {
        Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// Fill for a volume bar: a short leading-to-trailing gradient ending at the level's
    /// colour when smooth, a flat colour otherwise.
    static func volumeFill(for value: Double, smooth: Bool) -> AnyShapeStyle {
        let intensity = min(max(value, 0), 1)
        guard smooth else { return AnyShapeStyle(color(discreteComponents(for: intensity))) }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    color(smoothComponents(for: max(intensity - 0.15, 0))),
                    color(smoothComponents(for: intensity))
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    /// Rescales a colour's sRGB channels so its luminance (Rec. 709 weights) reaches
    /// `target`, clamping each channel at 1 (a minimum-brightness guarantee).
    static func scaled(_ color: Color, toLuminance target: Double) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let red = Double(rgb.redComponent)
        let green = Double(rgb.greenComponent)
        let blue = Double(rgb.blueComponent)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        guard luminance > 0 else { return color }
        let scale = target / luminance
        return Color(
            .sRGB,
            red: min(red * scale, 1),
            green: min(green * scale, 1),
            blue: min(blue * scale, 1),
            opacity: Double(rgb.alphaComponent)
        )
    }

    private static func blend(_ start: Components, _ end: Components, _ fraction: Double) -> Components {
        let t = min(max(fraction, 0), 1)
        return (
            start.red + (end.red - start.red) * t,
            start.green + (end.green - start.green) * t,
            start.blue + (end.blue - start.blue) * t
        )
    }
}

/// Draggable progress bar: a tertiary capsule track with a white, gradient,
/// accent or colour-coded fill, or 16 segments; thickens while dragged.
struct SystemHUDProgressBar: View {
    let value: CGFloat
    /// Colour-codes the fill like the volume bar when the setting allows it.
    var isVolume: Bool = true
    /// Inline bars are 5 pt (8 while dragged); standard rows 6 pt (9).
    var isInline: Bool = true
    var onDrag: ((CGFloat) -> Void)? = nil
    @ObservedObject var settings: SystemHUDSettings = .shared

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if settings.progressBarStyle == .segmented {
                    SystemHUDSegmentedBar(
                        value: value,
                        width: proxy.size.width,
                        useAccent: settings.useAccentColor,
                        glows: settings.glowEffect
                    )
                } else {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.tertiary)
                        fill(width: proxy.size.width)
                            .opacity(value <= 0 ? 0 : 1)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: proxy.size.width))
        }
        .frame(height: barHeight)
    }

    static func height(isInline: Bool, isDragging: Bool) -> CGFloat {
        isInline ? (isDragging ? 8 : 5) : (isDragging ? 9 : 6)
    }

    private var barHeight: CGFloat {
        Self.height(isInline: isInline, isDragging: isDragging)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                // Thickens the bar and moves the level in one smooth(0.3) transaction.
                withAnimation(.smooth(duration: 0.3)) {
                    isDragging = true
                    if width > 0 {
                        onDrag?(min(max(gesture.location.x / width, 0), 1))
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.3)) { isDragging = false }
            }
    }

    @ViewBuilder
    private func fill(width: CGFloat) -> some View {
        let fillWidth = max(0, min(width * value, width))
        Capsule()
            .fill(fillStyle)
            .frame(width: fillWidth)
            .shadow(color: shadowColor, radius: settings.glowEffect ? 8 : 0, x: 3)
    }

    private var fillStyle: AnyShapeStyle {
        if isVolume, settings.colorCodedVolume {
            return SystemHUDPalette.volumeFill(for: Double(value), smooth: settings.smoothColorGradient)
        }
        let accent = SystemHUDSettings.accentColor
        switch settings.progressBarStyle {
        case .gradient:
            return AnyShapeStyle(
                LinearGradient(
                    colors: settings.useAccentColor
                        ? [accent, SystemHUDPalette.scaled(accent, toLuminance: 0.2)]
                        : [.white, .white.opacity(0.2)],
                    startPoint: .trailing,
                    endPoint: .leading
                )
            )
        case .hierarchical, .segmented:
            return AnyShapeStyle(settings.useAccentColor ? accent : .white)
        }
    }

    private var shadowColor: Color {
        guard settings.glowEffect else { return .clear }
        return settings.useAccentColor
            ? SystemHUDPalette.scaled(SystemHUDSettings.accentColor, toLuminance: 0.7)
            : .white
    }
}

/// Segmented bar: 16 rounded bars 1.5 pt apart; a glow runs along the bars that
/// change when the level moves.
struct SystemHUDSegmentedBar: View {
    let value: CGFloat
    let width: CGFloat
    let useAccent: Bool
    let glows: Bool

    static let segmentCount = 16
    static let spacing: CGFloat = 1.5

    @State private var glowIndex: Int?
    @State private var waveTask: Task<Void, Never>?

    static func segmentWidth(totalWidth: CGFloat) -> CGFloat {
        max(3, (totalWidth - CGFloat(segmentCount - 1) * spacing) / CGFloat(segmentCount))
    }

    static func activeCount(for value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * CGFloat(segmentCount)).rounded())
    }

    var body: some View {
        let active = Self.activeCount(for: value)
        HStack(spacing: Self.spacing) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                let isActive = index < active
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? activeColor : Color.white.opacity(0.15))
                    .shadow(
                        color: glows && isActive ? glowColor(isGlowing: glowIndex == index) : .clear,
                        radius: glows ? (glowIndex == index ? 12 : (isActive ? 4 : 0)) : 0
                    )
                    .frame(width: Self.segmentWidth(totalWidth: width))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
                    .scaleEffect(glowIndex == index ? 1.15 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: glowIndex == index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(value <= 0 ? 0 : 1)
        .onChange(of: value) { oldValue, newValue in
            runWave(from: Self.activeCount(for: oldValue), to: Self.activeCount(for: newValue))
        }
        .onDisappear { waveTask?.cancel() }
    }

    private var activeColor: Color {
        useAccent ? SystemHUDSettings.accentColor : .white
    }

    private func glowColor(isGlowing: Bool) -> Color {
        guard useAccent else { return .white }
        return SystemHUDPalette.scaled(SystemHUDSettings.accentColor, toLuminance: isGlowing ? 0.8 : 0.7)
    }

    /// Lights each bar between the old and new level in turn, 15 ms apart, each for 0.2 s.
    private func runWave(from oldCount: Int, to newCount: Int) {
        guard oldCount != newCount else { return }
        let indices: [Int] = newCount > oldCount
            ? Array(max(0, oldCount)...min(Self.segmentCount - 1, newCount))
            : Array(stride(from: min(Self.segmentCount - 1, oldCount - 1), through: max(-1, newCount - 1), by: -1))
                .filter { $0 >= 0 }
        waveTask?.cancel()
        waveTask = Task { @MainActor in
            for index in indices {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { glowIndex = index }
                try? await Task.sleep(for: .milliseconds(15))
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { glowIndex = nil }
        }
    }
}

/// Percentage label: caption, semibold, monospaced digits, 28 pt, right-aligned.
struct SystemHUDPercentageLabel: View {
    let value: CGFloat
    @ObservedObject var settings: SystemHUDSettings = .shared

    var body: some View {
        if settings.showPercentages, settings.progressBarStyle != .segmented {
            Text(SystemHUDPresenter.percentageText(for: value))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
                .frame(width: 28, alignment: .trailing)
        }
    }
}
