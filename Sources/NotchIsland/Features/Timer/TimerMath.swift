import Foundation
import SwiftUI

/// Whole-second countdown arithmetic anchored to the wall clock, so a run that lasts
/// an hour does not drift the way a chain of one-second timers would.
struct TimerCountdownClock: Equatable, Sendable {
    /// Guards against a sleep that wakes a hair early and would otherwise show the same
    /// second twice.
    static let tickTolerance: TimeInterval = 0.0005

    let totalDuration: TimeInterval
    /// Whole seconds left when the current running stretch began. Negative in overtime.
    private(set) var remainingAtAnchor: TimeInterval
    /// When the current running stretch began; `nil` while paused.
    private(set) var anchor: Date?

    init(totalDuration: TimeInterval, startedAt: Date) {
        self.totalDuration = max(0, totalDuration.rounded(.down))
        remainingAtAnchor = self.totalDuration
        anchor = startedAt
    }

    var isPaused: Bool { anchor == nil }

    /// Seconds left at `now`, counting past zero into negative numbers.
    func remaining(at now: Date) -> TimeInterval {
        guard let anchor else { return remainingAtAnchor }
        let elapsed = max(0, now.timeIntervalSince(anchor))
        return remainingAtAnchor - (elapsed + Self.tickTolerance).rounded(.down)
    }

    /// Seconds spent so far, clamped to the total once the countdown has finished.
    func elapsed(at now: Date) -> TimeInterval {
        min(totalDuration, max(0, totalDuration - remaining(at: now)))
    }

    mutating func pause(at now: Date) {
        guard anchor != nil else { return }
        remainingAtAnchor = remaining(at: now)
        anchor = nil
    }

    mutating func resume(at now: Date) {
        guard anchor == nil else { return }
        anchor = now
    }

    /// How long to sleep until the displayed second changes again, or `nil` while paused.
    func delayUntilNextTick(from now: Date) -> TimeInterval? {
        guard let anchor else { return nil }
        let elapsed = max(0, now.timeIntervalSince(anchor))
        let fraction = elapsed - (elapsed + Self.tickTolerance).rounded(.down)
        return max(0.01, 1 - fraction)
    }
}

enum TimerFormatting {
    /// "M:SS" below an hour, "H:MM:SS" from one hour on. Negative values are prefixed
    /// with a minus sign, which is how overtime reads.
    static func timeString(_ seconds: TimeInterval) -> String {
        let magnitude = Int(abs(seconds).rounded(.down))
        let hours = magnitude / 3_600
        let minutes = (magnitude % 3_600) / 60
        let secs = magnitude % 60
        let body = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
        return seconds < 0 ? "-" + body : body
    }
}

enum TimerProgressMath {
    /// 0...1 while counting down; 1...2 in overtime, growing with the time spent past zero.
    static func progress(totalDuration: TimeInterval, elapsed: TimeInterval, remaining: TimeInterval, isOvertime: Bool) -> Double {
        guard totalDuration > 0 else { return 0 }
        if isOvertime {
            return 1 + min(1, abs(remaining) / totalDuration)
        }
        return min(1, max(0, elapsed / totalDuration))
    }

    /// The part of `progress` a ring or bar can draw.
    static func clamped(_ progress: Double) -> Double {
        min(1, max(0, progress))
    }
}

enum TimerColorRamp {
    /// Green for the first 60 % of a run, fading through yellow to red by 90 %, and red
    /// for the rest, including overtime.
    static func color(progress: Double, isOvertime: Bool) -> Color {
        guard !isOvertime else { return .red }
        if progress < 0.6 { return .green }
        if progress < 0.9 {
            let blend = (progress - 0.6) / 0.3
            return Color(red: 1 - (1 - blend) * 0.5, green: 1, blue: 0)
        }
        return .red
    }
}
