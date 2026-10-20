import Foundation
import Testing
@testable import Notchy

@MainActor
struct TimerTabModeTests {
    private func makeSettings() -> TimerSettings {
        let suite = "TimerTabModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return TimerSettings(defaults: defaults)
    }

    @Test func focusMovesInFiveMinuteSteps() {
        let focus = TimerTabMode.focus
        #expect(focus.adjusted(25 * 60, direction: 1) == 30 * 60)
        #expect(focus.adjusted(25 * 60, direction: -1) == 20 * 60)
        #expect(focus.adjusted(27 * 60, direction: 1) == 30 * 60, "an odd length snaps to the next step")
        #expect(focus.adjusted(27 * 60, direction: -1) == 25 * 60)
    }

    @Test func breakMovesInOneMinuteSteps() {
        let rest = TimerTabMode.rest
        #expect(rest.adjusted(5 * 60, direction: 1) == 6 * 60)
        #expect(rest.adjusted(5 * 60, direction: -1) == 4 * 60)
        #expect(rest.adjusted(90, direction: 1) == 120)
    }

    @Test func lengthsStayInRange() {
        #expect(TimerTabMode.focus.adjusted(5 * 60, direction: -1) == 5 * 60)
        #expect(TimerTabMode.focus.adjusted(180 * 60, direction: 1) == 180 * 60)
        #expect(TimerTabMode.rest.adjusted(60, direction: -1) == 60)
        #expect(TimerTabMode.rest.adjusted(60 * 60, direction: 1) == 60 * 60)
    }

    @Test func runningPresetNamesMapToModes() {
        #expect(TimerTabMode.mode(forPresetNamed: "Focus") == .focus)
        #expect(TimerTabMode.mode(forPresetNamed: "break") == .rest)
        #expect(TimerTabMode.mode(forPresetNamed: "Deep Work") == nil)
        #expect(TimerTabMode.mode(forPresetNamed: nil) == nil)
    }

    @Test func modeLengthsLiveInTheirPresets() {
        let settings = makeSettings()
        #expect(settings.preset(for: .focus).duration == 25 * 60)
        settings.setDuration(30 * 60, for: .focus)
        #expect(settings.preset(for: .focus).duration == 30 * 60)
        #expect(settings.presets.first { $0.name == "Focus" }?.duration == TimeInterval(30 * 60))
        #expect(settings.presets.count == TimerPreset.defaultPresets.count)
    }

    @Test func aRemovedPresetComesBackWhenItsLengthChanges() {
        let settings = makeSettings()
        settings.presets.removeAll { $0.name == "Break" }
        #expect(settings.preset(for: .rest).duration == 5 * 60, "falls back to the default")
        settings.setDuration(7 * 60, for: .rest)
        #expect(settings.presets.contains { $0.name == "Break" && $0.duration == 7 * 60 })
    }

    @Test func theChosenModeIsRemembered() {
        let suite = "TimerTabModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        TimerSettings(defaults: defaults).tabMode = .rest
        #expect(TimerSettings(defaults: defaults).tabMode == .rest)
    }
}
