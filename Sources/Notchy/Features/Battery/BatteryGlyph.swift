import AppKit
import SwiftUI

/// The header battery (`BatteryView`).
///
/// Filled style, the default: a light body with the charge as a coloured fill from the left
/// and the figure in dark rounded type centred over the whole body, a bolt or plug beside it
/// while on power, and a detached terminal. Outlined style: a thin `battery.0` outline around
/// a small inner bar, with the power glyph over it.
struct BatteryGlyph: View {
    let level: Int
    let isPluggedIn: Bool
    let isCharging: Bool
    let isInLowPowerMode: Bool
    var width: CGFloat = 26
    var showsPercentInside: Bool = true
    /// Bolt / plug glyph while on power.
    var showsPowerStatusIcon: Bool = true

    /// Yellow in Low Power Mode, red at 20 % or less on battery, green on power or full,
    /// otherwise white.
    static func color(level: Int, isPluggedIn: Bool, isCharging: Bool, isInLowPowerMode: Bool) -> Color {
        if isInLowPowerMode { return .yellow }
        if level <= 20, !isCharging, !isPluggedIn { return .red }
        if isCharging || isPluggedIn || level == 100 { return .green }
        return .white
    }

    /// Fill width inside a body `width` wide with `inset` padding: proportional, with a
    /// 2-pt floor only above zero so an empty battery reads as empty.
    static func fillWidth(level: Int, width: CGFloat, inset: CGFloat) -> CGFloat {
        let fraction = min(max(CGFloat(level) / 100, 0), 1)
        guard fraction > 0 else { return 0 }
        return max((width - inset * 2) * fraction, 2)
    }

    private var color: Color {
        Self.color(level: level, isPluggedIn: isPluggedIn, isCharging: isCharging, isInLowPowerMode: isInLowPowerMode)
    }

    private var statusSymbol: String? {
        guard showsPowerStatusIcon else { return nil }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    /// The outlined style's power glyph: a bolt while charging, an upright plug while plugged
    /// in. `powerplug.portrait` arrived with macOS 14's symbols; the sideways plug stands in.
    private var outlinedStatusGlyph: (fill: String, outline: String)? {
        guard showsPowerStatusIcon else { return nil }
        if isCharging { return ("bolt.fill", "bolt") }
        if isPluggedIn { return Self.uprightPlug }
        return nil
    }

    private static let uprightPlug: (fill: String, outline: String) =
        NSImage(systemSymbolName: "powerplug.portrait.fill", accessibilityDescription: nil) != nil
            ? ("powerplug.portrait.fill", "powerplug.portrait")
            : ("powerplug.fill", "powerplug")

    var body: some View {
        if showsPercentInside {
            filled
        } else {
            outlined
        }
    }

    private var filled: some View {
        let height = width * 0.52
        let inset: CGFloat = 1.5
        let bodyRadius = height * 0.34
        let bodyFill = Color.white.opacity(0.45)
        return HStack(spacing: height * 0.11) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                    .fill(bodyFill)
                RoundedRectangle(cornerRadius: bodyRadius - inset * 0.5, style: .continuous)
                    .fill(color)
                    .frame(width: Self.fillWidth(level: level, width: width, inset: inset))
                    .padding(inset)
                HStack(spacing: height * 0.04) {
                    Text(verbatim: "\(level)")
                        .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let statusSymbol {
                        Image(systemName: statusSymbol)
                            .font(.system(size: height * 0.42, weight: .bold))
                    }
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: width, alignment: .center)
            }
            .frame(width: width, height: height)

            RoundedRectangle(cornerRadius: height * 0.1, style: .continuous)
                .fill(bodyFill)
                .frame(width: height * 0.11, height: height * 0.36)
        }
        .animation(.smooth(duration: 0.3), value: level)
        .animation(.smooth(duration: 0.3), value: color)
    }

    private var outlined: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "battery.0")
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: width + 1)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(
                    width: CGFloat(min(max(level, 0), 100)) / 100 * (width - 6),
                    height: max(0, (width - 2.75) - 18)
                )
                .padding(.leading, 2)

            if let outlinedStatusGlyph {
                // The bitmaps are a white bolt / upright plug with a dark outline, fitted
                // to 17 x 17 and centred on a square as wide as the battery.
                ZStack {
                    Image(systemName: outlinedStatusGlyph.fill)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                    Image(systemName: outlinedStatusGlyph.outline)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.black)
                }
                .frame(width: 17, height: 17)
                .frame(width: width, height: width)
            }
        }
        .animation(.smooth(duration: 0.3), value: level)
    }
}

/// The popover under the header battery: level, capacity, power state, time to full and a
/// shortcut to the Battery pane of System Settings. 280 pt wide.
struct BatteryMenuView: View {
    let snapshot: BatterySnapshot
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(verbatim: "\(snapshot.level)%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Max Capacity: \(snapshot.maxCapacity)%")
                    .font(.subheadline)
                if snapshot.isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                }
                if snapshot.isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                }
                if snapshot.isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                }
                if snapshot.timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(snapshot.timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                }
                if !snapshot.isCharging, snapshot.isPluggedIn, snapshot.level >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 8)

            Divider()

            Button(action: openBatterySettings) {
                Label("Battery Settings", systemImage: "gearshape")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundStyle(.primary)
    }

    private func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else { return }
        NSWorkspace.shared.open(url)
        onDismiss()
    }
}
