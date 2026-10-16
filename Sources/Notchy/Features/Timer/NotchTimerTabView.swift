import AppKit
import SwiftUI

/// Timer tab content. Idle: a custom-duration composer on the left and a column of preset
/// cards on the right. Running: pause and cancel buttons, the timer's name with a status
/// badge, a large countdown (or a progress ring) and a thin progress bar.
struct NotchTimerTabView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var manager: TimerManager
    @ObservedObject private var settings: TimerSettings
    @State private var hours = 0
    @State private var minutes = 10
    @State private var seconds = 0
    /// The colour a run starts with is kept for the whole run so the card does not drift
    /// along the ramp while the user watches it.
    @State private var lockedAccent: Color?
    @FocusState private var focusedField: TimerDurationFieldKind?

    init(model: NotchViewModel, manager: TimerManager = .shared, settings: TimerSettings = .shared) {
        self.model = model
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = max(130, proxy.size.height - 12)
            HStack(alignment: .top, spacing: manager.isActive ? 0 : 20) {
                leftColumn(contentHeight: contentHeight)
                if showsPresetColumn {
                    Divider()
                        .frame(height: max(0, contentHeight - 8))
                        .opacity(0.2)
                    presetColumn(contentHeight: contentHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: contentHeight, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .animation(.smooth, value: manager.isActive)
        .onAppear {
            syncFields(with: settings.customDuration)
            lockAccentIfNeeded()
        }
        .onChange(of: settings.customDuration) { _, duration in syncFields(with: duration) }
        .onChange(of: hours) { _, _ in storeCustomDuration() }
        .onChange(of: minutes) { _, _ in storeCustomDuration() }
        .onChange(of: seconds) { _, _ in storeCustomDuration() }
        .onChange(of: manager.isActive) { _, isActive in
            if isActive {
                lockAccentIfNeeded()
            } else {
                lockedAccent = nil
            }
        }
        .onChange(of: manager.activePresetID) { _, _ in
            if manager.isActive, lockedAccent == nil { lockAccentIfNeeded() }
        }
        .onChange(of: focusedField) { _, field in
            model.setKeyboardFocus(field != nil)
        }
    }

    // MARK: - Columns

    private func leftColumn(contentHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if manager.isActive {
                Spacer(minLength: 0)
                activeTimerCard
                Spacer(minLength: 0)
            } else {
                composer
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: contentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    private var showsPresetColumn: Bool {
        !manager.isActive && settings.showsPresetsInTab
    }

    private func presetColumn(contentHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            if settings.presets.isEmpty {
                Text("Configure presets in Settings to see them here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                let listHeight = min(max(0, contentHeight - 16), CGFloat(settings.presets.count) * 60 + 4)
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(settings.presets) { preset in
                            TimerPresetCard(preset: preset, isActive: manager.activePresetID == preset.id) {
                                startPreset(preset)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                }
                .frame(height: listHeight)
            }
        }
        .frame(width: 210, alignment: .leading)
        .frame(maxHeight: contentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    // MARK: - Running

    private var activeTimerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                controlSection
                    .frame(width: 128, alignment: .leading)
                titleSection
                countdownSection
            }
            if settings.showsProgress, settings.progressStyle == .bar {
                progressBar
            }
        }
        .padding(.horizontal, 4)
    }

    private var controlSection: some View {
        HStack(spacing: 10) {
            if !manager.isOvertime {
                TimerControlButton(
                    icon: manager.isPaused ? "play.fill" : "pause.fill",
                    background: accent.opacity(0.32),
                    help: manager.isPaused ? "Resume" : "Pause"
                ) {
                    manager.togglePause()
                }
                TimerControlButton(icon: "xmark", background: Color.white.opacity(0.16), help: "Cancel") {
                    manager.stop()
                }
            } else {
                TimerControlButton(icon: "stop.fill", background: Color.white.opacity(0.16), help: "Stop") {
                    manager.stop()
                }
            }
        }
    }

    private var titleSection: some View {
        GeometryReader { proxy in
            let status = manager.statusBadgeText
            let spacing: CGFloat = status == nil ? 0 : 8
            let badgeWidth = status.map(statusBadgeWidth(for:)) ?? 0
            let marqueeWidth = max(48, proxy.size.width - badgeWidth - spacing)
            HStack(alignment: .center, spacing: spacing) {
                TimerMarqueeText(
                    text: manager.name,
                    font: .system(size: 20, weight: .semibold),
                    measuringFont: TimerTextMeasurer.systemFont(size: 20, weight: .semibold),
                    color: .white,
                    minDuration: 0.2,
                    frameWidth: marqueeWidth
                )
                .frame(width: marqueeWidth, height: 24, alignment: .leading)

                if let status {
                    statusBadge(status)
                        .frame(width: badgeWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var countdownSection: some View {
        if settings.showsProgress, settings.progressStyle == .ring {
            TimerProgressRing(
                progress: manager.progress,
                tint: accent,
                timeText: manager.formattedRemainingTime,
                isOvertime: manager.isOvertime,
                remainingTime: manager.remainingTime
            )
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                Text(manager.formattedRemainingTime)
                    .font(.system(size: 36, weight: .black, design: .monospaced))
                    .foregroundStyle(manager.isOvertime ? Color.red : .white)
                    .contentTransition(.numericText(countsDown: !manager.isOvertime))
                    .animation(.smooth(duration: 0.25), value: manager.remainingTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if manager.isOvertime {
                    Text("Overtime")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 190, alignment: .trailing)
        }
    }

    private var progressBar: some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent)
                    .frame(height: 4)
                    .scaleEffect(x: CGFloat(TimerProgressMath.clamped(manager.progress)), y: 1, anchor: .leading)
                    .animation(.smooth(duration: 0.25), value: manager.progress)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func statusBadge(_ text: String) -> some View {
        let color = manager.isOvertime ? Color.red : accent
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private func statusBadgeWidth(for text: String) -> CGFloat {
        TimerTextMeasurer.width(of: text, font: TimerTextMeasurer.systemFont(size: 12, weight: .semibold)) + 24
    }

    // MARK: - Idle

    private var composer: some View {
        Group {
            if settings.showsPresetsInTab {
                VStack(alignment: .leading, spacing: 12) {
                    durationRow(fieldWidth: 64)
                    HStack(spacing: 10) {
                        startButton
                        resetButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    durationRow(fieldWidth: 78)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 10) {
                        startButton
                        resetButton
                    }
                    .frame(width: 210, alignment: .top)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func durationRow(fieldWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 8) {
            TimerDurationField(label: "Hours", value: $hours, range: 0...23, width: fieldWidth, kind: .hours, focus: $focusedField, onSubmit: startCustomTimer)
            colon
            TimerDurationField(label: "Minutes", value: $minutes, range: 0...59, width: fieldWidth, kind: .minutes, focus: $focusedField, onSubmit: startCustomTimer)
            colon
            TimerDurationField(label: "Seconds", value: $seconds, range: 0...59, width: fieldWidth, kind: .seconds, focus: $focusedField, onSubmit: startCustomTimer)
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 26, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.65))
            .padding(.bottom, 20)
    }

    private static let startGreen = Color(red: 0.142, green: 0.633, blue: 0.265)

    private var isStartDisabled: Bool { customDuration == 0 }

    private var startButton: some View {
        Button(action: startCustomTimer) {
            Label("Start", systemImage: "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Self.startGreen.opacity(isStartDisabled ? 0.5 : 1))
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .opacity(isStartDisabled ? 0.7 : 1)
        .disabled(isStartDisabled)
        .help("Start the custom timer")
    }

    private var resetButton: some View {
        Button(action: resetFields) {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .help("Clear the duration")
    }

    // MARK: - Actions and state

    private var accent: Color { lockedAccent ?? manager.accentColor }

    private func lockAccentIfNeeded() {
        if manager.isActive { lockedAccent = manager.accentColor }
    }

    private var customDuration: TimeInterval {
        TimerDurationComponents(hours: hours, minutes: minutes, seconds: seconds).duration
    }

    private func startCustomTimer() {
        let duration = customDuration
        guard duration > 0 else { return }
        focusedField = nil
        withAnimation(.smooth) {
            manager.start(duration: duration, name: "Custom Timer")
        }
    }

    private func startPreset(_ preset: TimerPreset) {
        focusedField = nil
        withAnimation(.smooth) {
            manager.start(preset: preset)
        }
    }

    private func resetFields() {
        withAnimation(.smooth(duration: 0.2)) {
            hours = 0
            minutes = 0
            seconds = 0
        }
        settings.customDuration = 0
    }

    private func syncFields(with duration: TimeInterval) {
        let components = TimerDurationComponents(duration: duration)
        if hours != components.hours { hours = components.hours }
        if minutes != components.minutes { minutes = components.minutes }
        if seconds != components.seconds { seconds = components.seconds }
    }

    private func storeCustomDuration() {
        let duration = customDuration
        if settings.customDuration != duration { settings.customDuration = duration }
    }
}

// MARK: - Pieces

enum TimerDurationFieldKind: Hashable {
    case hours
    case minutes
    case seconds
}

/// A two-digit field with its unit underneath. Accepts digits only and clamps to range.
private struct TimerDurationField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let width: CGFloat
    let kind: TimerDurationFieldKind
    let focus: FocusState<TimerDurationFieldKind?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            TextField("00", text: text)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .tint(.white)
                .frame(width: width, height: 46)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused(focus, equals: kind)
                .onSubmit(onSubmit)
                .accessibilityLabel(label)

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var text: Binding<String> {
        Binding(
            get: { String(format: "%02d", value) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                let number = Int(digits.suffix(4)) ?? 0
                value = min(max(range.lowerBound, number), range.upperBound)
            }
        )
    }
}

/// A 46-pt round button whose glyph swaps with a symbol-replace effect.
private struct TimerControlButton: View {
    let icon: String
    let background: Color
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 46, height: 46)
                .background(background.opacity(isHovering ? 0.95 : 0.8))
                .clipShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}

/// A 110-pt ring with the countdown inside, used when the progress style is Ring.
private struct TimerProgressRing: View {
    let progress: Double
    let tint: Color
    let timeText: String
    let isOvertime: Bool
    let remainingTime: TimeInterval

    private var clampedProgress: Double { TimerProgressMath.clamped(progress) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: clampedProgress)
            Text(timeText)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(isOvertime ? Color.red : .white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(countsDown: !isOvertime))
                .animation(.smooth(duration: 0.25), value: remainingTime)
        }
        .frame(width: 110, height: 110)
    }
}

/// One preset: colour dot, name and duration, and a play glyph that becomes a check mark
/// while that preset is running.
private struct TimerPresetCard: View {
    let preset: TimerPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(preset.formattedDuration)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(preset.color)

                Spacer(minLength: 0)

                Image(systemName: isActive ? "checkmark" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? preset.color : Color.secondary)
                    .padding(6)
                    .background(isActive ? preset.color.opacity(0.2) : Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? preset.color.opacity(0.12) : Color.white.opacity(0.04))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Start \(preset.name)")
        .accessibilityLabel("\(preset.name), \(preset.formattedDuration)")
    }
}
