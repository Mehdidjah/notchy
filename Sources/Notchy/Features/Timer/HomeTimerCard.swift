import SwiftUI

/// Home-tab timer card: the timer's name, the time left in large rounded digits, and pause and
/// cancel buttons, with the elapsed share stroked along the card's edge from the top centre.
/// Idle, it offers the default duration with a start button.
///
/// The edge advances once a second without animation, so nothing redraws between ticks.
struct HomeTimerCard: View {
    static let edgeWidth: CGFloat = 3

    @ObservedObject private var manager: TimerManager
    @ObservedObject private var settings: TimerSettings
    private let openTimerTab: (() -> Void)?

    init(manager: TimerManager = .shared, settings: TimerSettings = .shared, openTimerTab: (() -> Void)? = nil) {
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
        self.openTimerTab = openTimerTab
    }

    /// The preset's or the chosen solid colour, orange otherwise, red in overtime.
    private var accent: Color {
        if manager.isOvertime { return HomeCardPalette.red }
        switch settings.iconColorMode {
        case .solid: return settings.solidColor.color
        case .adaptive: return manager.activePreset?.color ?? HomeCardPalette.orange
        }
    }

    private var edge: HomeTimerEdge {
        HomeTimerEdge(cornerRadius: HomeCardLayout.cornerRadius, inset: Self.edgeWidth / 2)
    }

    var body: some View {
        ZStack {
            HomeCardBackground(cornerStyle: .circular)
            edge.stroke(HomeCardPalette.track, lineWidth: Self.edgeWidth)
            if manager.isActive {
                edge
                    .trim(from: 0, to: TimerProgressMath.clamped(manager.progress))
                    .stroke(accent, style: StrokeStyle(lineWidth: Self.edgeWidth, lineCap: .round))
            }
            VStack(spacing: 0) {
                Text(manager.isActive ? manager.name : "Timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HomeCardPalette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(manager.isActive ? manager.formattedRemainingTime : TimerFormatting.timeString(settings.customDuration))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(manager.isActive ? accent : HomeCardPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 2)
                controls
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: .circular))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(manager.isActive ? "\(manager.name), \(manager.statusText)" : "Timer")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if manager.isActive {
                if !manager.isFinished {
                    HomeRoundButton(
                        symbol: manager.isPaused ? "play.fill" : "pause.fill",
                        tint: accent,
                        help: manager.isPaused ? "Resume" : "Pause"
                    ) { manager.togglePause() }
                }
                HomeRoundButton(symbol: "xmark", help: "Cancel timer") { manager.stop() }
            } else {
                HomeRoundButton(symbol: "play.fill", tint: HomeCardPalette.orange, help: "Start timer") {
                    manager.start(duration: settings.customDuration)
                }
                if let openTimerTab {
                    HomeRoundButton(symbol: "list.bullet", help: "Timer presets", action: openTimerTab)
                }
            }
        }
    }
}

/// A rounded rectangle's outline drawn clockwise from the middle of its top edge, so trimming
/// it fills the edge like a clock hand. Inset by half the stroke so the stroke stays inside.
struct HomeTimerEdge: Shape {
    var cornerRadius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, rect.width / 2, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
