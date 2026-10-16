import AppKit
import Combine
import SwiftUI

/// Everything the Focus wings draw, apart from sizes that depend on the notch.
struct FocusWingDisplay: Equatable {
    var isVisible = false
    var isExpanded = false
    var showsInactiveIcon = false
    var symbolName = "moon.fill"
    var iconColor: Color = FocusModeKind.doNotDisturb.accentColor
    var labelText = ""
    var labelColor: Color = FocusModeKind.doNotDisturb.accentColor
    var toastMode = false
    var showLabelSetting = true
    var isDoNotDisturb = true

    /// The fields that decide the wing widths; when only the rest changes the island keeps its size.
    struct WidthKey: Equatable {
        var isExpanded: Bool
        var showsInactiveIcon: Bool
        var labelText: String
        var toastMode: Bool
        var showLabelSetting: Bool
        var isDoNotDisturb: Bool
    }

    var widthKey: WidthKey {
        WidthKey(
            isExpanded: isExpanded,
            showsInactiveIcon: showsInactiveIcon,
            labelText: labelText,
            toastMode: toastMode,
            showLabelSetting: showLabelSetting,
            isDoNotDisturb: isDoNotDisturb
        )
    }
}

/// What the Focus wings draw. Updated only while the activity shows, so the glyph and label
/// fold away with the island instead of vanishing a frame early.
@MainActor
final class FocusWingModel: ObservableObject {
    @Published fileprivate(set) var display = FocusWingDisplay()
}

/// Text sizes for the Focus label, measured with the same 12-pt semibold system font.
@MainActor
enum FocusTextMetrics {
    static func labelWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Labels wider than "Do Not Disturb" scroll instead of widening the wing further.
    static var marqueeThreshold: CGFloat { labelWidth("Do Not Disturb") }

    /// Width of the label as drawn: 12-pt semibold in the rounded design. The marquee scrolls
    /// by this so its two copies meet seamlessly.
    static func renderedWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// Wing sizes for the Focus activity, after Atoll's DoNotDisturbLiveActivity.
struct FocusWingLayout: Equatable {
    var iconWidth: CGFloat
    var labelWidth: CGFloat
    var showsLabel: Bool
    var usesMarquee: Bool

    /// Width the marquee scrolls inside: the wing less 8 pt, never under 48.
    var marqueeFrameWidth: CGFloat { max(48, labelWidth - 8) }

    @MainActor
    static func make(display: FocusWingDisplay, closedHeight: CGFloat, notchWidth: CGFloat) -> FocusWingLayout {
        make(
            display: display,
            closedHeight: closedHeight,
            notchWidth: notchWidth,
            labelIntrinsicWidth: FocusTextMetrics.labelWidth(display.labelText),
            marqueeThreshold: FocusTextMetrics.marqueeThreshold
        )
    }

    static func make(
        display: FocusWingDisplay,
        closedHeight: CGFloat,
        notchWidth: CGFloat,
        labelIntrinsicWidth: CGFloat,
        marqueeThreshold: CGFloat
    ) -> FocusWingLayout {
        let minimal = max(closedHeight - 12, 24)
        let wingsOpen = display.isExpanded || display.showsInactiveIcon
        let iconWidth = wingsOpen ? minimal : 0
        let hasText = !display.labelText.isEmpty
        let showsLabel = display.toastMode
            ? display.isExpanded && hasText
            : display.showLabelSetting && display.isExpanded && hasText
        let usesMarquee = showsLabel && labelIntrinsicWidth > marqueeThreshold

        let labelWidth: CGFloat
        if !showsLabel {
            labelWidth = display.toastMode ? 0 : (wingsOpen ? minimal : 0)
        } else if display.toastMode {
            labelWidth = max(labelIntrinsicWidth + 26, minimal)
        } else {
            var desired = max(notchWidth * 0.52, 136)
            if display.isDoNotDisturb { desired = max(desired, 164) }
            if !usesMarquee { desired = max(desired, labelIntrinsicWidth + 8) }
            labelWidth = max(desired, minimal)
        }
        return FocusWingLayout(iconWidth: iconWidth, labelWidth: labelWidth, showsLabel: showsLabel, usesMarquee: usesMarquee)
    }
}

/// The active Focus on the closed notch (Atoll's DoNotDisturbLiveActivity): the mode's glyph
/// on the left, its name on the right, both in the mode's accent colour.
///
/// Persistent mode stays while Focus is on and folds away as soon as it ends: shipped Atoll
/// mounts this view only while Focus is on or an "Off" toast is playing, so its persistent-mode
/// pop animation never reaches the screen. Toast mode shows "On" for 1.8 s, and "Off" with a
/// white glyph and label for 1.5 s, then folds away; switching modes while on replays the toast.
@MainActor
final class FocusActivity: ClosedLiveActivity {
    static let identifier = "focus"

    let activityID = FocusActivity.identifier
    let priority = ClosedActivityPriority.focus
    weak var center: IslandActivityCenter?

    private let monitor: FocusMonitor
    private var settings: FocusSettings { monitor.settings }

    private(set) var isExpanded = false
    private(set) var showsInactiveIcon = false
    /// True for the frame in which the wings sit shut before springing open again; the
    /// activity stays on the island meanwhile, as Atoll's view stays mounted.
    private var holdsBaseline = false
    /// The current presentation; only changed through `commit`.
    private(set) var display = FocusWingDisplay()
    let wingModel = FocusWingModel()

    private struct Inputs: Equatable {
        var enabled: Bool
        var active: Bool
        var toastTrigger: UUID
        var toastMode: Bool
    }

    private var lastInputs: Inputs?
    private var collapseTask: Task<Void, Never>?
    private var reopenTask: Task<Void, Never>?
    private let changes = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    /// Toast linger times, from Atoll.
    static let toastOnDuration: Duration = .milliseconds(1_800)
    static let toastOffDuration: Duration = .milliseconds(1_500)
    /// How long the wings stay shut before a replayed "on" springs them open: one frame, so
    /// the shut state is drawn before the spring starts from it.
    static let baselineHold: Duration = .milliseconds(20)

    init(monitor: FocusMonitor = .shared) {
        self.monitor = monitor
        monitor.objectWillChange
            .merge(with: monitor.settings.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &cancellables)
        sync()
    }

    var isActivityVisible: Bool { display.isVisible }

    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func leftWingWidth(in context: ClosedActivityContext) -> CGFloat {
        layout(in: context).iconWidth
    }

    func rightWingWidth(in context: ClosedActivityContext) -> CGFloat {
        layout(in: context).labelWidth
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(FocusIconWing(model: wingModel, closedHeight: context.closedHeight, notchWidth: context.notchWidth))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(FocusLabelWing(model: wingModel, closedHeight: context.closedHeight, notchWidth: context.notchWidth))
    }

    func layout(in context: ClosedActivityContext) -> FocusWingLayout {
        FocusWingLayout.make(display: display, closedHeight: context.closedHeight, notchWidth: context.notchWidth)
    }

    // MARK: - State machine

    /// Reacts to the monitor and settings. Runs on the main queue after they have changed.
    func sync() {
        let now = Inputs(
            enabled: settings.enableDoNotDisturbDetection && settings.showDoNotDisturbIndicator,
            active: monitor.isActive,
            toastTrigger: monitor.toastTrigger,
            toastMode: settings.focusIndicatorNonPersistent
        )
        let previous = lastInputs
        lastInputs = now

        if !now.enabled {
            cancelTimers()
            transition(.smooth(duration: 0.32)) {
                isExpanded = false
                showsInactiveIcon = false
            }
            return
        }

        if let previous, previous.enabled {
            if now.active != previous.active {
                cancelTimers()
                if now.active {
                    expand(toast: now.toastMode, fromShutBaseline: true)
                } else {
                    turnOff(toast: now.toastMode)
                }
            } else if now.active, now.toastMode, now.toastTrigger != previous.toastTrigger {
                cancelTimers()
                expand(toast: true, fromShutBaseline: true)
            } else if now.active, now.toastMode != previous.toastMode {
                cancelTimers()
                expand(toast: now.toastMode)
            }
        } else if now.active {
            // First look, or the indicator was just switched on while Focus is on.
            expand(toast: now.toastMode)
        }
        // Name, mode or label-setting changes resize the wings with Atoll's 0.3 s smooth.
        transition(.smooth(duration: 0.3)) {}
    }

    /// Opens the wings with Atoll's spring and, in toast mode, schedules the 1.8 s collapse.
    ///
    /// With `fromShutBaseline`, wings that are already open (an "Off" toast, or an "On" toast
    /// when the mode switches) first snap shut without animation and spring open a frame
    /// later, so the toast visibly plays again, as in Atoll.
    private func expand(toast: Bool, fromShutBaseline: Bool = false) {
        if fromShutBaseline, isExpanded || showsInactiveIcon {
            transition(nil) {
                holdsBaseline = true
                isExpanded = false
                showsInactiveIcon = false
            }
            reopenTask = after(Self.baselineHold) { activity in
                activity.holdsBaseline = false
                activity.expand(toast: toast)
            }
            return
        }
        transition(.spring(response: 0.35, dampingFraction: 0.85)) {
            holdsBaseline = false
            showsInactiveIcon = false
            isExpanded = true
        }
        if toast {
            collapseTask = after(Self.toastOnDuration) { activity in
                activity.transition(.smooth(duration: 0.32)) {
                    activity.isExpanded = false
                    activity.showsInactiveIcon = false
                }
            }
        }
    }

    private func turnOff(toast: Bool) {
        guard toast else {
            // Persistent: the view leaves with the manager's 0.25 s smooth as Focus ends.
            transition(.smooth(duration: 0.25)) {
                isExpanded = false
                showsInactiveIcon = false
            }
            return
        }
        // Toast: the wings reopen with the white "off" glyph and "Off", then fold after 1.5 s.
        transition(.spring(response: 0.3, dampingFraction: 0.9)) { isExpanded = true }
        transition(.smooth(duration: 0.2)) { showsInactiveIcon = true }
        collapseTask = after(Self.toastOffDuration) { activity in
            activity.transition(.smooth(duration: 0.32)) {
                activity.isExpanded = false
                activity.showsInactiveIcon = false
            }
        }
    }

    private func after(_ delay: Duration, _ work: @escaping @MainActor (FocusActivity) -> Void) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            work(self)
        }
    }

    private func cancelTimers() {
        collapseTask?.cancel()
        collapseTask = nil
        reopenTask?.cancel()
        reopenTask = nil
        holdsBaseline = false
    }

    /// Applies `changes` and, inside the same animation, lets the island re-read the wings.
    private func transition(_ animation: Animation?, _ changes: () -> Void) {
        withAnimation(animation) {
            changes()
            commit()
        }
    }

    private func commit() {
        let next = makeDisplay()
        guard next != display else { return }
        let visibilityChanged = next.isVisible != display.isVisible
        let widthChanged = next.isVisible && next.widthKey != display.widthKey
        display = next
        if next.isVisible { wingModel.display = next }
        guard visibilityChanged || widthChanged else { return }
        // Inside the caller's animation, so the island resizes with the same curve.
        center?.reevaluate()
        changes.send()
    }

    private func makeDisplay() -> FocusWingDisplay {
        let appearance = monitor.appearance
        let active = monitor.isActive
        let toast = settings.focusIndicatorNonPersistent
        let enabled = settings.enableDoNotDisturbDetection && settings.showDoNotDisturbIndicator
        let inactiveLook = !active && showsInactiveIcon
        return FocusWingDisplay(
            isVisible: enabled && (isExpanded || showsInactiveIcon || holdsBaseline),
            isExpanded: isExpanded,
            showsInactiveIcon: showsInactiveIcon,
            symbolName: inactiveLook ? appearance.inactiveSymbolName : appearance.symbolName,
            iconColor: inactiveLook ? .white : appearance.accent,
            labelText: Self.labelText(
                active: active,
                toast: toast,
                showLabel: settings.showDoNotDisturbLabel,
                modeName: monitor.modeName,
                kind: appearance.kind
            ),
            labelColor: toast && !active ? .white : appearance.accent,
            toastMode: toast,
            showLabelSetting: settings.showDoNotDisturbLabel,
            isDoNotDisturb: appearance.kind == .doNotDisturb
        )
    }

    /// "On"/"Off" in toast mode; otherwise the mode's name when the label is enabled.
    static func labelText(active: Bool, toast: Bool, showLabel: Bool, modeName: String, kind: FocusModeKind) -> String {
        if toast { return active ? "On" : "Off" }
        guard showLabel else { return "" }
        let trimmed = modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if kind == .doNotDisturb { return "Do Not Disturb" }
        return kind.displayName.isEmpty ? "Focus" : kind.displayName
    }
}

// MARK: - Wings

private struct FocusIconWing: View {
    @ObservedObject var model: FocusWingModel
    let closedHeight: CGFloat
    let notchWidth: CGFloat

    var body: some View {
        let display = model.display
        let layout = FocusWingLayout.make(display: display, closedHeight: closedHeight, notchWidth: notchWidth)
        Color.clear
            .overlay(alignment: .center) {
                if layout.iconWidth > 0 {
                    Image(systemName: display.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(display.iconColor)
                        .contentTransition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: layout.iconWidth)
            .accessibilityHidden(true)
    }
}

private struct FocusLabelWing: View {
    @ObservedObject var model: FocusWingModel
    let closedHeight: CGFloat
    let notchWidth: CGFloat

    var body: some View {
        let display = model.display
        let layout = FocusWingLayout.make(display: display, closedHeight: closedHeight, notchWidth: notchWidth)
        Color.clear
            .overlay(alignment: .trailing) {
                if layout.showsLabel {
                    Group {
                        if layout.usesMarquee {
                            FocusMarqueeText(
                                text: display.labelText,
                                color: display.labelColor,
                                frameWidth: layout.marqueeFrameWidth
                            )
                            .frame(width: layout.marqueeFrameWidth, alignment: .trailing)
                        } else {
                            Text(display.labelText)
                                .font(FocusMarqueeText.font)
                                .foregroundStyle(display.labelColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.opacity)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: layout.showsLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(display.isVisible ? "Focus: \(display.labelText)" : "Focus off")
    }
}

/// A single line that, when wider than its frame, waits 0.1 s, then repeatedly pauses 0.4 s
/// and scrolls left at 30 pt/s with a 20-pt gap before the repeat, snapping back each time.
/// The row is 13 pt tall (the 10-pt caption size times 1.3), as in Atoll's marquee.
struct FocusMarqueeText: View {
    static let font = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let gap: CGFloat = 20
    static let pointsPerSecond: CGFloat = 30
    static let startDelay: Duration = .milliseconds(100)
    static let pause: Duration = .milliseconds(400)
    static let rowHeight: CGFloat = 13

    let text: String
    let color: Color
    let frameWidth: CGFloat
    @State private var offset: CGFloat = 0

    var body: some View {
        let textWidth = FocusTextMetrics.renderedWidth(text)
        let scrolls = textWidth > frameWidth
        HStack(spacing: Self.gap) {
            Text(text)
            Text(text).opacity(scrolls ? 1 : 0)
        }
        .font(Self.font)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: Self.rowHeight)
        .task(id: "\(text)|\(frameWidth)") {
            await scroll(textWidth: textWidth, scrolls: scrolls)
        }
    }

    private func scroll(textWidth: CGFloat, scrolls: Bool) async {
        reset()
        guard scrolls else { return }
        try? await Task.sleep(for: Self.startDelay)
        let travel = textWidth + Self.gap
        let seconds = Double(textWidth / Self.pointsPerSecond)
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: seconds)) { offset = -travel }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            reset()
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
    }
}
