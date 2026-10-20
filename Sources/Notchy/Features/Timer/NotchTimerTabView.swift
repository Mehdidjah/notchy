import SwiftUI

/// Timer tab: a focus/break timer. The mode name and status sit on top; below, a progress ring
/// with the mode's glyph, the FOCUS/BREAK chips, the time with − and + to change the length,
/// and Start/Pause with a reset button. A running timer from anywhere (a preset, the Home card)
/// shows here too.
struct NotchTimerTabView: View {
    let model: NotchViewModel
    @ObservedObject private var manager: TimerManager
    @ObservedObject private var settings: TimerSettings

    init(model: NotchViewModel, manager: TimerManager = .shared, settings: TimerSettings = .shared) {
        self.model = model
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .center, spacing: 28) {
                TimerFocusRing(progress: ringProgress, accent: accent, systemImage: glyph)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 8) {
                    modeChips
                    timeRow
                    controls
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.25), value: settings.tabMode)
        .animation(.smooth(duration: 0.25), value: manager.isActive)
    }

    // MARK: State

    /// The mode on screen: the running timer's, or the chosen one while idle.
    private var shownMode: TimerTabMode? {
        manager.isActive ? TimerTabMode.mode(forPresetNamed: manager.activePreset?.name) : settings.tabMode
    }

    private var idlePreset: TimerPreset { settings.preset(for: settings.tabMode) }

    private var title: String { manager.isActive ? manager.name : settings.tabMode.title }

    private var accent: Color { manager.isActive ? manager.accentColor : idlePreset.color }

    private var glyph: String { shownMode?.systemImage ?? "timer" }

    private var ringProgress: Double { manager.isActive ? min(max(manager.progress, 0), 1) : 0 }

    private var timeText: String {
        manager.isActive ? manager.formattedRemainingTime : TimerFormatting.timeString(idlePreset.duration)
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(manager.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(manager.isOvertime ? Color.red.opacity(0.9) : .white.opacity(0.5))
        }
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            ForEach(TimerTabMode.allCases, id: \.self) { mode in
                let preset = settings.preset(for: mode)
                // While a timer runs the mode can't change; the chips stay readable rather than
                // greyed out, and only the unselected one fades.
                TimerModeChip(
                    title: mode.title.uppercased(),
                    systemImage: mode.systemImage,
                    color: preset.color,
                    isSelected: shownMode == mode,
                    isLocked: manager.isActive
                ) {
                    guard !manager.isActive else { return }
                    settings.tabMode = mode
                }
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 12) {
            TimerRoundButton(systemImage: "minus", size: 26, help: "Shorter") { adjust(-1) }
                .disabled(manager.isActive || idlePreset.duration <= settings.tabMode.allowedRange.lowerBound)
            Text(timeText)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(manager.isOvertime ? Color.red.opacity(0.9) : .white)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 136)
            TimerRoundButton(systemImage: "plus", size: 26, help: "Longer") { adjust(1) }
                .disabled(manager.isActive || idlePreset.duration >= settings.tabMode.allowedRange.upperBound)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: primaryImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            TimerRoundButton(systemImage: "arrow.counterclockwise", size: 30, help: resetHelp) { reset() }
                .disabled(!canReset)
        }
    }

    // MARK: Actions

    private var primaryTitle: String {
        if manager.isOvertime { return "Stop" }
        if manager.isPaused { return "Resume" }
        if manager.isActive { return "Pause" }
        return "Start"
    }

    private var primaryImage: String {
        if manager.isOvertime { return "stop.fill" }
        if manager.isActive, !manager.isPaused { return "pause.fill" }
        return "play.fill"
    }

    private func primaryAction() {
        if manager.isOvertime {
            manager.stop()
        } else if manager.isPaused {
            manager.resume()
        } else if manager.isActive {
            manager.pause()
        } else {
            manager.start(preset: idlePreset)
        }
    }

    private var canReset: Bool {
        manager.isActive || idlePreset.duration != settings.tabMode.defaultDuration
    }

    private var resetHelp: String {
        manager.isActive ? "Stop and reset the timer" : "Back to \(TimerFormatting.timeString(settings.tabMode.defaultDuration))"
    }

    /// Running: stops the timer. Idle: puts the mode back to its default length.
    private func reset() {
        if manager.isActive {
            manager.stop()
        } else {
            settings.setDuration(settings.tabMode.defaultDuration, for: settings.tabMode)
        }
    }

    private func adjust(_ direction: Int) {
        let mode = settings.tabMode
        settings.setDuration(mode.adjusted(idlePreset.duration, direction: direction), for: mode)
    }
}

// MARK: - Pieces

/// A ring that fills clockwise as the timer runs, with a dot at its leading edge and the mode's
/// glyph in the middle. Ticks once a second, so changes are not animated frame by frame.
struct TimerFocusRing: View {
    let progress: Double
    let accent: Color
    let systemImage: String
    private let lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2
            let angle = Angle.degrees(progress * 360 - 90)
            ZStack {
                // Inset by half the line so the stroke's centre line, and therefore the arc's
                // end, sits exactly at `radius`, where the dot is drawn.
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress \(Int((progress * 100).rounded())) percent")
    }
}

/// FOCUS / BREAK: a small capsule, outlined and tinted when selected.
private struct TimerModeChip: View {
    let title: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 11, weight: .heavy)).tracking(0.8)
            }
            .foregroundStyle(isSelected ? color : Color.white.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground)
            .contentShape(Capsule())
            .opacity(isLocked && !isSelected ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The outline is a filled capsule under a slightly smaller one rather than a stroke, so its
    /// ends stay perfectly round in every renderer. The island behind it is always black.
    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            ZStack {
                Capsule().fill(color)
                Capsule().inset(by: 1.2).fill(Color.black)
                Capsule().inset(by: 1.2).fill(color.opacity(0.16))
            }
        } else {
            Capsule().fill(Color.white.opacity(0.07))
        }
    }
}

/// A grey round button with one glyph, for − / + and reset.
private struct TimerRoundButton: View {
    let systemImage: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.85 : 0.3))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
