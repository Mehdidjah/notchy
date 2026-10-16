import AppKit
import SwiftUI

/// Sizes for the closed-notch timer activity, computed from the same inputs the view
/// draws with so the island's width can be known before anything renders.
struct TimerLiveActivityLayout: Equatable, Sendable {
    struct Inputs: Equatable, Sendable {
        var contentHeight: CGFloat
        var name: String
        var countdownText: String
        var isFinished: Bool
        var isOvertime: Bool
        var showsCountdown: Bool
        /// The name is visible, whether permanently, transiently, or because the run finished.
        var showsLabel: Bool
        var showsProgress: Bool
        var progressStyle: TimerProgressStyle
        var showsControls: Bool
    }

    static let wingPadding: CGFloat = 22
    static let ringStrokeWidth: CGFloat = 3
    static let controlSpacing: CGFloat = 10
    static let labelFontSize: CGFloat = 12
    static let countdownFontSize: CGFloat = 13

    let contentHeight: CGFloat
    let showsCountdown: Bool
    let showsLabel: Bool
    let showsControls: Bool
    let isOvertime: Bool
    /// Ring style with a countdown: the ring wraps the glyph on the left.
    let ringWrapsIcon: Bool
    /// Ring style without a countdown: the ring sits alone on the right.
    let ringOnRight: Bool
    let showsBarProgress: Bool
    let iconWidth: CGFloat
    let iconRingDiameter: CGFloat
    let iconGlyphFrame: CGFloat
    let showsInfoSection: Bool
    let infoWidth: CGFloat
    let infoTextWidth: CGFloat
    let infoNeedsMarquee: Bool
    let showsBarInInfo: Bool
    let infoBarWidth: CGFloat
    let leftWingWidth: CGFloat
    let rightRingWidth: CGFloat
    let rightRingDiameter: CGFloat
    let countdownTextWidth: CGFloat
    let countdownWidth: CGFloat
    let inlineButtonSize: CGFloat
    let inlineIconSize: CGFloat
    let controlCount: Int
    let controlsWidth: CGFloat
    let rightWingWidth: CGFloat

    var totalWingWidth: CGFloat { leftWingWidth + rightWingWidth }

    init(_ inputs: Inputs) {
        let height = max(0, inputs.contentHeight)
        contentHeight = height
        showsCountdown = inputs.showsCountdown
        showsLabel = inputs.showsLabel
        showsControls = inputs.showsControls
        isOvertime = inputs.isOvertime

        let showsRing = inputs.showsProgress && inputs.progressStyle == .ring
        showsBarProgress = inputs.showsProgress && inputs.progressStyle == .bar
        ringWrapsIcon = showsRing && inputs.showsCountdown
        ringOnRight = showsRing && !inputs.showsCountdown

        iconWidth = ringWrapsIcon ? max(height - 6, 28) : height
        iconRingDiameter = ringWrapsIcon ? max(min(iconWidth, height - 2), 22) : iconWidth
        iconGlyphFrame = ringWrapsIcon ? max(iconRingDiameter - 12, 16) : max(18, iconWidth - 6)

        let titleWidth = TimerTextMeasurer.width(
            of: inputs.name,
            font: TimerTextMeasurer.systemFont(size: Self.labelFontSize, weight: .medium)
        )
        showsBarInInfo = showsBarProgress && !inputs.showsCountdown
        showsInfoSection = inputs.showsLabel || showsBarInInfo
        let infoContentWidth: CGFloat = if !showsInfoSection {
            0
        } else if inputs.showsLabel {
            min(max(titleWidth, 44), 220)
        } else {
            min(max(height * 1.4, 64), 220)
        }
        infoWidth = showsInfoSection ? infoContentWidth + 18 : 0
        let infoAvailable = max(0, infoWidth - 10)
        let infoSafe = max(44, infoAvailable - 6)
        infoTextWidth = min(max(titleWidth, 44), infoSafe)
        infoNeedsMarquee = inputs.showsLabel
            && (inputs.isFinished || inputs.isOvertime || titleWidth > infoAvailable)
        infoBarWidth = inputs.showsLabel ? infoTextWidth : infoAvailable

        var left = iconWidth + Self.wingPadding / 2
        if showsInfoSection { left += 8 + infoWidth }
        leftWingWidth = left

        rightRingWidth = ringOnRight ? 30 : 0
        rightRingDiameter = max(min(height - 4, 26), 20)
        inlineButtonSize = min(max(height - 4, 20), 26)
        inlineIconSize = max(inlineButtonSize * 0.6, 12)
        controlCount = inputs.showsControls ? (inputs.isOvertime ? 1 : 2) : 0
        controlsWidth = CGFloat(controlCount) * inlineButtonSize
            + CGFloat(max(0, controlCount - 1)) * Self.controlSpacing

        countdownTextWidth = TimerTextMeasurer.width(
            of: inputs.countdownText,
            font: TimerTextMeasurer.monospacedFont(size: Self.countdownFontSize, weight: .semibold)
        )
        countdownWidth = inputs.showsCountdown ? max(countdownTextWidth + 16, 72) : 0

        var right = Self.wingPadding
        if ringOnRight { right += rightRingWidth }
        if ringOnRight, inputs.showsCountdown { right += Self.controlSpacing }
        if inputs.showsCountdown { right += countdownWidth }
        if inputs.showsControls {
            if ringOnRight || inputs.showsCountdown { right += Self.controlSpacing }
            right += controlsWidth
        }
        rightWingWidth = right
    }

    /// The wings' content is 12 pt shorter than the notch while idle and fills it on hover.
    static func contentHeight(collapsedHeight: CGFloat, isHovering: Bool) -> CGFloat {
        let base = collapsedHeight - (isHovering ? NotchSilhouette.hoverSwell : 0)
        return max(0, base - (isHovering ? 0 : 12))
    }

    /// The layout for the live timer, or `nil` when nothing should be shown on the
    /// closed notch. The view draws from exactly this, so the width it yields is the
    /// width the island needs.
    @MainActor
    static func current(
        collapsedHeight: CGFloat,
        isHovering: Bool,
        manager: TimerManager = .shared,
        settings: TimerSettings = .shared
    ) -> TimerLiveActivityLayout? {
        guard TimerLiveActivityView.isPresentable(manager: manager, settings: settings) else { return nil }
        return TimerLiveActivityLayout(inputs(
            contentHeight: contentHeight(collapsedHeight: collapsedHeight, isHovering: isHovering),
            manager: manager,
            settings: settings
        ))
    }

    @MainActor
    static func inputs(contentHeight: CGFloat, manager: TimerManager, settings: TimerSettings) -> Inputs {
        let finishedOrOver = manager.isFinished || manager.isOvertime
        return Inputs(
            contentHeight: contentHeight,
            name: manager.name,
            countdownText: manager.formattedRemainingTime,
            isFinished: manager.isFinished,
            isOvertime: manager.isOvertime,
            showsCountdown: settings.showsCountdown,
            showsLabel: settings.showsLabel || manager.showsTransientLabel || finishedOrOver,
            showsProgress: settings.showsProgress,
            progressStyle: settings.progressStyle,
            showsControls: settings.inlineControlsEnabled && manager.allowsManualInteraction
        )
    }

    /// Extra width the collapsed island needs beyond the notch itself while a timer shows.
    @MainActor
    static func extraCollapsedWidth(
        collapsedHeight: CGFloat,
        isHovering: Bool,
        manager: TimerManager = .shared,
        settings: TimerSettings = .shared
    ) -> CGFloat {
        current(collapsedHeight: collapsedHeight, isHovering: isHovering, manager: manager, settings: settings)?
            .totalWingWidth ?? 0
    }
}

/// The running timer on the closed notch: a tinted timer glyph on the left wing (with
/// an optional ring and the timer's name), a black middle that covers the hardware
/// notch, and the countdown with pause and stop buttons on the right wing.
struct TimerLiveActivityView: View {
    /// Which part to draw: the whole activity, or one wing for the island's live-activity slots.
    enum Part: Sendable { case full, left, right }

    /// Width of the black middle that covers the hardware notch, including any hover swell.
    let notchWidth: CGFloat
    let part: Part
    /// Full height of the collapsed island, including any hover swell.
    let height: CGFloat
    let isHovering: Bool
    @ObservedObject private var manager: TimerManager
    @ObservedObject private var settings: TimerSettings

    init(
        notchWidth: CGFloat,
        height: CGFloat,
        isHovering: Bool,
        part: Part = .full,
        manager: TimerManager = .shared,
        settings: TimerSettings = .shared
    ) {
        self.notchWidth = notchWidth
        self.part = part
        self.height = height
        self.isHovering = isHovering
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
    }

    /// Whether the closed notch should show the timer at all.
    static func isPresentable(manager: TimerManager = .shared, settings: TimerSettings = .shared) -> Bool {
        manager.isActive && settings.liveActivityEnabled
    }

    private var contentHeight: CGFloat {
        TimerLiveActivityLayout.contentHeight(collapsedHeight: height, isHovering: isHovering)
    }

    private var layout: TimerLiveActivityLayout {
        TimerLiveActivityLayout(
            TimerLiveActivityLayout.inputs(contentHeight: contentHeight, manager: manager, settings: settings)
        )
    }

    private var glyphColor: Color { manager.accentColor }

    private var clampedProgress: Double { TimerProgressMath.clamped(manager.progress) }

    var body: some View {
        let layout = layout
        HStack(spacing: 0) {
            if part != .right { leftWing(layout) }
            if part == .full {
                Rectangle()
                    .fill(.black)
                    .frame(width: notchWidth, height: layout.contentHeight)
            }
            if part != .left { rightWing(layout) }
        }
        .frame(height: part == .full ? height : layout.contentHeight, alignment: .center)
        .contentShape(Rectangle())
        .animation(.smooth, value: layout.showsInfoSection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(manager.name), \(manager.formattedRemainingTime) remaining")
    }

    // MARK: - Wings

    private func leftWing(_ layout: TimerLiveActivityLayout) -> some View {
        Color.clear
            .frame(width: layout.leftWingWidth, height: layout.contentHeight)
            .overlay(alignment: .leading) {
                HStack(spacing: layout.showsInfoSection ? 8 : 0) {
                    iconSection(layout)
                    if layout.showsInfoSection {
                        infoSection(layout)
                    }
                }
                .padding(.leading, TimerLiveActivityLayout.wingPadding / 2)
            }
    }

    private func rightWing(_ layout: TimerLiveActivityLayout) -> some View {
        Color.clear
            .frame(width: layout.rightWingWidth, height: layout.contentHeight)
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    if layout.ringOnRight {
                        ringSection(layout)
                    }
                    if layout.showsCountdown {
                        countdownSection(layout)
                            .padding(.leading, layout.ringOnRight ? TimerLiveActivityLayout.controlSpacing : 0)
                    }
                    if layout.showsControls {
                        controlsSection(layout)
                            .padding(
                                .leading,
                                layout.ringOnRight || layout.showsCountdown ? TimerLiveActivityLayout.controlSpacing : 0
                            )
                    }
                }
                .padding(.trailing, TimerLiveActivityLayout.wingPadding / 2 - 9)
            }
    }

    // MARK: - Sections

    private func iconSection(_ layout: TimerLiveActivityLayout) -> some View {
        ZStack {
            if layout.ringWrapsIcon {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: TimerLiveActivityLayout.ringStrokeWidth)
                    .frame(width: layout.iconRingDiameter, height: layout.iconRingDiameter)
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: TimerLiveActivityLayout.ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                    .frame(width: layout.iconRingDiameter, height: layout.iconRingDiameter)
            }
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: layout.iconGlyphFrame, height: layout.iconGlyphFrame)
        }
        .frame(
            width: layout.ringWrapsIcon ? layout.iconRingDiameter : layout.iconWidth,
            height: layout.contentHeight
        )
    }

    private func infoSection(_ layout: TimerLiveActivityLayout) -> some View {
        Rectangle()
            .fill(.black)
            .frame(width: layout.infoWidth, height: layout.contentHeight)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: layout.showsBarInInfo ? 4 : 0) {
                    if layout.showsLabel {
                        if layout.infoNeedsMarquee {
                            TimerMarqueeText(
                                text: manager.name,
                                font: .system(size: TimerLiveActivityLayout.labelFontSize, weight: .medium),
                                measuringFont: TimerTextMeasurer.systemFont(size: TimerLiveActivityLayout.labelFontSize, weight: .medium),
                                color: .white,
                                minDuration: 0.25,
                                frameWidth: layout.infoTextWidth
                            )
                        } else {
                            Text(manager.name)
                                .font(.system(size: TimerLiveActivityLayout.labelFontSize, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .frame(width: layout.infoTextWidth, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    if layout.showsBarInInfo {
                        progressBar(width: layout.infoBarWidth)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
            }
            .animation(.smooth, value: manager.isFinished)
    }

    private func ringSection(_ layout: TimerLiveActivityLayout) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: TimerLiveActivityLayout.ringStrokeWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(glyphColor, style: StrokeStyle(lineWidth: TimerLiveActivityLayout.ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: layout.rightRingDiameter, height: layout.rightRingDiameter)
        .frame(width: layout.rightRingWidth, height: layout.contentHeight)
    }

    private func countdownSection(_ layout: TimerLiveActivityLayout) -> some View {
        VStack(spacing: 4) {
            Text(manager.formattedRemainingTime)
                .font(.system(size: TimerLiveActivityLayout.countdownFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(manager.isOvertime ? Color.red : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText(countsDown: !manager.isOvertime))
                .animation(.smooth(duration: 0.25), value: manager.remainingTime)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if layout.showsBarProgress {
                progressBar(width: max(layout.countdownTextWidth, 1))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: layout.countdownWidth, height: layout.contentHeight)
    }

    private func controlsSection(_ layout: TimerLiveActivityLayout) -> some View {
        HStack(spacing: TimerLiveActivityLayout.controlSpacing) {
            if !manager.isOvertime {
                controlButton(
                    layout,
                    icon: manager.isPaused ? "play.fill" : "pause.fill",
                    background: Color.white.opacity(0.14),
                    help: manager.isPaused ? "Resume" : "Pause"
                ) {
                    manager.togglePause()
                }
            }
            controlButton(
                layout,
                icon: manager.isOvertime ? "stop.fill" : "xmark",
                background: manager.isOvertime ? Color.red.opacity(0.24) : Color.white.opacity(0.14),
                help: manager.isOvertime ? "Stop" : "Cancel"
            ) {
                manager.stop()
            }
        }
        .frame(height: layout.contentHeight)
    }

    private func controlButton(
        _ layout: TimerLiveActivityLayout,
        icon: String,
        background: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: layout.inlineIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: layout.inlineButtonSize, height: layout.inlineButtonSize)
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func progressBar(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(width: width, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(glyphColor)
                    .frame(width: width * CGFloat(clampedProgress))
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
            }
    }
}
