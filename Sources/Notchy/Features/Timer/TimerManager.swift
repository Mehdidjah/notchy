import Combine
import Foundation
import SwiftUI

/// The one countdown the island runs. Lives independently of the notch views so a
/// timer keeps going while the island is closed; views observe it from wherever they are.
@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager(settings: .shared)

    /// Where the running timer came from. Only manual timers exist for now; the case
    /// stays so a system-mirrored timer can be added without changing the views.
    enum Source: Sendable {
        case none
        case manual
    }

    @Published private(set) var isActive = false
    @Published private(set) var name = "Timer"
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var isPaused = false
    /// The countdown reached zero. Stays true through overtime.
    @Published private(set) var isFinished = false
    /// Counting past zero, shown as "-M:SS", until the user stops the timer.
    @Published private(set) var isOvertime = false
    @Published private(set) var activePresetID: UUID?
    @Published private(set) var source: Source = .none
    @Published private(set) var startedAt: Date?
    let settings: TimerSettings
    private let sound: any TimerSoundPlaying
    private let notifier: any TimerCompletionNotifying
    private let clock: @Sendable () -> Date
    private var countdown: TimerCountdownClock?
    private var tickTask: Task<Void, Never>?
    /// Identifies the current run so delayed work from an earlier run cannot touch a
    /// timer started in the meantime.
    private(set) var sessionID: UUID?

    init(
        settings: TimerSettings,
        sound: (any TimerSoundPlaying)? = nil,
        notifier: (any TimerCompletionNotifying)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.sound = sound ?? SystemTimerSound()
        self.notifier = notifier ?? TimerUserNotifier()
        self.clock = clock
    }

    // MARK: - Derived state

    var isRunning: Bool { isActive && !isPaused }

    var progress: Double {
        TimerProgressMath.progress(
            totalDuration: totalDuration,
            elapsed: elapsedTime,
            remaining: remainingTime,
            isOvertime: isOvertime
        )
    }

    /// Progress colour on the green-yellow-red ramp.
    var rampColor: Color {
        TimerColorRamp.color(progress: progress, isOvertime: isOvertime)
    }

    var activePreset: TimerPreset? {
        settings.preset(withID: activePresetID)
    }

    /// The colour the glyph and progress should use under the current colour mode.
    var accentColor: Color {
        switch settings.iconColorMode {
        case .adaptive: activePreset?.color ?? rampColor
        case .solid: settings.solidColor.color
        }
    }

    var formattedRemainingTime: String {
        TimerFormatting.timeString(remainingTime)
    }

    var statusText: String {
        if isOvertime { return "Overtime" }
        if isPaused { return "Paused" }
        if isActive { return "Running" }
        return "Ready"
    }

    /// The badge shown beside the timer name, most urgent first.
    var statusBadgeText: String? {
        if isOvertime { return "Overtime" }
        if isPaused { return "Paused" }
        if isFinished { return "Completed" }
        return nil
    }

    var allowsManualInteraction: Bool { true }

    // MARK: - Control

    func start(preset: TimerPreset) {
        start(duration: preset.duration, name: preset.name, presetID: preset.id)
    }

    func start(duration: TimeInterval, name: String = "Timer", presetID: UUID? = nil) {
        let whole = max(0, duration.rounded(.down))
        guard whole > 0 else { return }
        tickTask?.cancel()
        sound.stop()
        sessionID = UUID()
        let now = clock()
        countdown = TimerCountdownClock(totalDuration: whole, startedAt: now)
        source = .manual
        self.name = name.isEmpty ? "Timer" : name
        totalDuration = whole
        remainingTime = whole
        elapsedTime = 0
        isPaused = false
        isFinished = false
        isOvertime = false
        activePresetID = presetID
        startedAt = now
        withAnimation(.smooth) {
            isActive = true
        }
        if settings.notificationsEnabled {
            notifier.prepare()
        }
        scheduleTicks()
    }

    func pause() {
        guard isActive, !isPaused, source == .manual else { return }
        countdown?.pause(at: clock())
        tickTask?.cancel()
        tickTask = nil
        isPaused = true
    }

    func resume() {
        guard isActive, isPaused, source == .manual else { return }
        countdown?.resume(at: clock())
        isPaused = false
        scheduleTicks()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    /// Ends the run at once, silencing the alert if it is ringing.
    func stop() {
        tickTask?.cancel()
        tickTask = nil
        sound.stop()
        sessionID = nil
        countdown = nil
        withAnimation(.smooth) {
            isActive = false
        }
        name = "Timer"
        totalDuration = 0
        remainingTime = 0
        elapsedTime = 0
        isPaused = false
        isFinished = false
        isOvertime = false
        activePresetID = nil
        source = .none
        startedAt = nil
    }

    // MARK: - Ticking

    /// Recomputes the published time from the clock. Exposed so tests can step a run
    /// without waiting; the tick loop calls it once a second.
    func tick(now: Date? = nil) {
        guard isActive, !isPaused, let countdown else { return }
        let now = now ?? clock()
        let remaining = countdown.remaining(at: now)
        let crossedZero = remainingTime > 0 && remaining <= 0
        remainingTime = remaining
        elapsedTime = countdown.elapsed(at: now)
        if crossedZero {
            isFinished = true
            if settings.soundEnabled {
                sound.play(named: settings.soundName, looping: true)
            }
            if settings.notificationsEnabled {
                notifier.notifyCompletion(name: name, duration: totalDuration)
            }
        }
        if remaining < 0, !isOvertime {
            isOvertime = true
        }
    }

    private func scheduleTicks() {
        tickTask?.cancel()
        let session = sessionID
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionID == session,
                      let countdown = self.countdown,
                      let delay = countdown.delayUntilNextTick(from: self.clock()) else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }
}
