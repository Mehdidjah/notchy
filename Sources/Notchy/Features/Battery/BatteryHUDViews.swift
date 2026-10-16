import SwiftUI

/// Tint of a battery alert: yellow in Low Power Mode; otherwise red for a low alert
/// or for charging at 20 % or less, green for the rest.
enum BatteryHUDTint {
    static func color(kind: BatteryHUDKind, level: Int, isLowPowerMode: Bool) -> Color {
        if isLowPowerMode { return .yellow }
        switch kind {
        case .charging: return level <= 20 ? .red : .green
        case .lowBattery: return .red
        case .fullBattery: return .green
        }
    }

    /// Title of the compact row.
    static func compactTitle(for kind: BatteryHUDKind) -> String {
        switch kind {
        case .charging: "Charging"
        case .lowBattery: "Low Battery"
        case .fullBattery: "Full Battery"
        }
    }
}

/// Left wing of the compact alert: the title, 16 pt in from the island's edge. Text longer
/// than the wing runs under the black centre, as it does under the hardware notch.
struct BatteryHUDCompactLeadingWing: View {
    let kind: BatteryHUDKind

    var body: some View {
        Text(verbatim: BatteryHUDTint.compactTitle(for: kind))
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Right wing of the compact alert: the percentage in the tint and a small pill battery.
struct BatteryHUDCompactTrailingWing: View {
    @ObservedObject var controller: BatteryHUDController
    /// Observed so the live level and Low Power Mode redraw the wing.
    @ObservedObject var monitor: BatteryMonitor
    let kind: BatteryHUDKind

    var body: some View {
        let level = controller.displayedLevel
        let tint = BatteryHUDTint.color(kind: kind, level: level, isLowPowerMode: controller.displayedLowPowerMode)
        HStack(spacing: 6) {
            Text(verbatim: "\(level)%")
                .font(.system(size: 14))
                .foregroundStyle(tint)
            BatteryHUDPill(level: level, tint: tint)
        }
        .fixedSize()
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(BatteryHUDTint.compactTitle(for: kind)), \(level) percent")
    }
}

/// The pill battery of the compact alert: a 28 x 16 body filled from the left and a detached
/// 2 x 6 terminal that lights up only at 100 %.
struct BatteryHUDPill: View {
    let level: Int
    let tint: Color

    var body: some View {
        let clamped = min(max(level, 0), 100)
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.3))
                GeometryReader { proxy in
                    Rectangle()
                        .fill(tint.gradient)
                        .frame(width: max(0, CGFloat(clamped) / 100 * proxy.size.width))
                }
            }
            .frame(width: 28, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(clamped == 100 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.3).gradient))
                .frame(width: 2, height: 6)
        }
    }
}

/// The standard alert's card under the notch: title and advice on the left, an animated
/// battery illustration on the right, sitting 20 pt above the island's bottom edge.
struct BatteryHUDStandardCard: View {
    @ObservedObject var controller: BatteryHUDController
    /// Observed so the live level and Low Power Mode redraw the card.
    @ObservedObject var monitor: BatteryMonitor
    let kind: BatteryHUDKind

    @State private var pulse = false
    /// The full alert opens on the battery and swaps to the MagSafe connector after 2 s.
    @State private var showsFullBattery = true
    /// The MagSafe light turns from orange to green after 3 s.
    @State private var ledIsOrange = true

    var body: some View {
        let level = controller.displayedLevel
        let lowPowerMode = controller.displayedLowPowerMode
        let tint = BatteryHUDTint.color(kind: kind, level: level, isLowPowerMode: lowPowerMode)
        HStack {
            VStack(alignment: .leading, spacing: kind == .lowBattery ? 2 : 3) {
                title(level: level, tint: tint)
                description(lowPowerMode: lowPowerMode)
            }
            Spacer()
            indicator(lowPowerMode: lowPowerMode)
        }
        .padding(.leading, kind == .lowBattery ? 40 : 35)
        .padding(.trailing, kind == .lowBattery ? 45 : 40)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { startPulse(lowPowerMode: lowPowerMode) }
        .task { await runFullBatterySequence() }
        .accessibilityElement(children: .combine)
    }

    private func title(level: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: kind == .lowBattery ? "Battery Low" : "Full Battery")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            Text(verbatim: "\(level)%")
                .font(.system(size: kind == .lowBattery ? 12 : 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func description(lowPowerMode: Bool) -> some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if lowPowerMode {
                Text(Self.lowPowerModeAdvice)
                    .font(.system(size: 10, weight: .medium))
            } else {
                Text(verbatim: "Turn on Low Power Mode or it\nis recommended to charge it.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .fullBattery:
            Text(verbatim: "Your Mac is fully charged.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.gray.opacity(0.6))
                .lineLimit(1)
        }
    }

    /// "Low Power Mode enabled" in yellow, then the advice in grey.
    private static var lowPowerModeAdvice: AttributedString {
        var enabled = AttributedString("Low Power Mode enabled")
        enabled.swiftUI.foregroundColor = Color.yellow
        var advice = AttributedString(", it is recommended to charge it.")
        advice.swiftUI.foregroundColor = Color.gray.opacity(0.6)
        return enabled + advice
    }

    @ViewBuilder
    private func indicator(lowPowerMode: Bool) -> some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            BatteryLowIndicator(tint: lowPowerMode ? .yellow : .red, pulses: !lowPowerMode, pulse: pulse)
        case .fullBattery:
            if showsFullBattery {
                BatteryFullIndicator(tint: lowPowerMode ? .yellow : .green, pulse: pulse)
                    .transition(.opacity.combined(with: .scale))
            } else {
                MagSafeConnectorIndicator(ledIsOrange: ledIsOrange)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func startPulse(lowPowerMode: Bool) {
        pulse = false
        showsFullBattery = true
        ledIsOrange = true
        let pulses = kind == .fullBattery || (kind == .lowBattery && !lowPowerMode)
        guard pulses else { return }
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func runFullBatterySequence() async {
        guard kind == .fullBattery else { return }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.4)) { showsFullBattery = false }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.2)) { ledIsOrange = false }
    }
}

/// A 70 x 40 tinted lozenge with an empty battery and a short charge bar near its left end.
/// The red variant breathes: the bar fades, and an outline swells from the bar to the
/// lozenge's height and back.
private struct BatteryLowIndicator: View {
    let tint: Color
    let pulses: Bool
    let pulse: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(tint.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 40, height: 24)
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(tint.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulses ? (pulse ? 1 : 0.3) : 1)
                .offset(x: -15)

            if pulses {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(tint.opacity(0.9), lineWidth: 1.5)
                    .frame(width: pulse ? 8 : 30, height: pulse ? 14 : 32)
                    .offset(x: -15)
                    .opacity(pulse ? 0.3 : 1)
            }
        }
    }
}

/// A 70 x 40 tinted lozenge holding a full battery whose charge block breathes.
private struct BatteryFullIndicator: View {
    let tint: Color
    let pulse: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(tint.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tint.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    }
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }
}

/// A side view of a MagSafe plug: cable, connector body with its status light, and the
/// port edge. The light glows orange, then green once the battery is full.
private struct MagSafeConnectorIndicator: View {
    let ledIsOrange: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)
                Circle()
                    .fill(ledIsOrange ? Color.orange : Color.green)
                    .shadow(color: ledIsOrange ? .orange : .green, radius: 5)
                    .frame(width: 5, height: 5)
            }
            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
    }
}
