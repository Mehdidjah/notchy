import Foundation

/// The two modes the Timer tab switches between. Each one is backed by the preset of the same
/// name, so changing a mode's length in the tab also changes the preset everywhere else.
enum TimerTabMode: String, CaseIterable, Sendable {
    case focus
    case rest

    var title: String {
        switch self {
        case .focus: "Focus"
        case .rest: "Break"
        }
    }

    /// The name of the preset that holds this mode's length.
    var presetName: String { title }

    var systemImage: String {
        switch self {
        case .focus: "hourglass"
        case .rest: "cup.and.saucer.fill"
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .focus: 25 * 60
        case .rest: 5 * 60
        }
    }

    var defaultColor: TimerColorComponents {
        switch self {
        case .focus: .systemOrange
        case .rest: .systemGreen
        }
    }

    /// How much one press of − or + changes the length.
    var step: TimeInterval {
        switch self {
        case .focus: 5 * 60
        case .rest: 60
        }
    }

    var allowedRange: ClosedRange<TimeInterval> {
        switch self {
        case .focus: 5 * 60...180 * 60
        case .rest: 60...60 * 60
        }
    }

    /// The length after pressing − (`direction` < 0) or + (> 0): moves to the next multiple of
    /// `step` in that direction, so an odd length like 27:00 lands on 25:00 or 30:00, and stays
    /// within `allowedRange`.
    func adjusted(_ duration: TimeInterval, direction: Int) -> TimeInterval {
        guard direction != 0 else { return clamped(duration) }
        let steps = duration / step
        let target: Double
        if direction > 0 {
            target = (steps.rounded(.down) + 1) * step
        } else {
            let lower = steps.rounded(.up) - 1
            target = lower * step
        }
        return clamped(target)
    }

    func clamped(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, allowedRange.lowerBound), allowedRange.upperBound)
    }

    /// The mode a running timer belongs to, from the preset it was started with.
    static func mode(forPresetNamed name: String?) -> TimerTabMode? {
        guard let name else { return nil }
        return allCases.first { $0.presetName.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension TimerSettings {
    /// The preset behind `mode`, or a default one when the user removed it.
    func preset(for mode: TimerTabMode) -> TimerPreset {
        presets.first { $0.name.caseInsensitiveCompare(mode.presetName) == .orderedSame }
            ?? TimerPreset(name: mode.presetName, duration: mode.defaultDuration, colorComponents: mode.defaultColor)
    }

    /// Changes the length of `mode`'s preset, adding the preset back if it was removed.
    func setDuration(_ duration: TimeInterval, for mode: TimerTabMode) {
        let length = mode.clamped(duration)
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(mode.presetName) == .orderedSame }) {
            guard presets[index].duration != length else { return }
            presets[index].duration = length
        } else {
            presets.append(TimerPreset(name: mode.presetName, duration: length, colorComponents: mode.defaultColor))
        }
    }
}
