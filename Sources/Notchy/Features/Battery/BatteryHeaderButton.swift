import SwiftUI

/// The battery at the right end of the open island's header (`DynamicIslandBatteryView`
/// at `batteryWidth: 30`): an optional "NN%" label and the battery glyph. Pressing it scales
/// it to 0.95; releasing opens the battery popover. Renders nothing when the indicator is
/// switched off or the Mac has no battery.
struct BatteryHeaderButton: View {
    @ObservedObject private var monitor: BatteryMonitor
    @ObservedObject private var settings: BatterySettings
    @State private var isPressed = false
    @State private var isMenuPresented = false
    /// Pointer over the popover. The island stays open only while the popover is both
    /// shown and hovered (`isBatteryPopoverActive`).
    @State private var isHoveringPopover = false
    /// What was last reported to the host, so the hold is always released.
    @State private var reportedActive = false

    /// Header battery width.
    static let glyphWidth: CGFloat = 30

    init(monitor: BatteryMonitor = .shared, settings: BatterySettings = .shared) {
        _monitor = ObservedObject(wrappedValue: monitor)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        if settings.showBatteryIndicator, monitor.state.hasBattery {
            chip
        }
    }

    private var chip: some View {
        let state = monitor.state
        return HStack {
            // The figure goes in one place or the other, never both.
            if settings.showBatteryPercentage, !settings.showBatteryPercentInside {
                ZStack(alignment: .trailing) {
                    Text(verbatim: "100%")
                        .font(.callout)
                        .hidden()
                    Text(verbatim: "\(state.level)%")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            BatteryGlyph(
                level: state.level,
                isPluggedIn: state.isPluggedIn,
                isCharging: state.isCharging,
                isInLowPowerMode: state.isInLowPowerMode,
                width: Self.glyphWidth,
                showsPercentInside: settings.showBatteryPercentInside,
                showsPowerStatusIcon: settings.showPowerStatusIcons
            )
        }
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation {
                        isPressed = false
                        isMenuPresented.toggle()
                    }
                }
        )
        .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
            BatteryMenuView(snapshot: monitor.state) { isMenuPresented = false }
                .onHover { hovering in isHoveringPopover = hovering }
        }
        .onChange(of: isMenuPresented) { _, presented in
            if !presented { isHoveringPopover = false }
            reportPopoverActive()
        }
        .onChange(of: isHoveringPopover) { _, _ in reportPopoverActive() }
        .onDisappear {
            isHoveringPopover = false
            reportPopoverActive(force: false)
        }
        .help("Battery")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: state))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isMenuPresented.toggle() }
    }

    private func reportPopoverActive(force: Bool? = nil) {
        let active = force ?? (isMenuPresented && isHoveringPopover)
        guard active != reportedActive else { return }
        reportedActive = active
        BatteryFeature.onPopoverPresentationChanged?(active)
    }

    private func accessibilityText(for state: BatterySnapshot) -> String {
        var parts = ["Battery \(state.level) percent"]
        if state.isCharging {
            parts.append("charging")
        } else if state.isPluggedIn {
            parts.append("plugged in")
        }
        if state.isInLowPowerMode { parts.append("Low Power Mode") }
        return parts.joined(separator: ", ")
    }
}
