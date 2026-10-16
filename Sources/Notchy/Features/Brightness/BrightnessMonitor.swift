import AppKit
import CoreGraphics
import Foundation
import IOKit
import os

/// Watches the built-in display's brightness so the island can show its brightness HUD.
/// There is no public API for the brightness slider, so the level is read from the I/O
/// Registry (a public read that needs no permission) and converted back to the slider's
/// scale with `BrightnessCurve`.
///
/// Brightness keys move the slider by 1/16 (1/64 with Shift-Option) within a fraction of a
/// second, while auto-brightness drifts slowly and macOS dims the screen on its own before
/// sleep, after a stretch without input. A change is reported only when it is quick and
/// follows input: a brightness key seen by the media-key tap or a media key / pointer press
/// allows fine steps, other input only full ones, and no input at all never shows the HUD.
///
/// Three things move the reading without the user touching the slider, and are absorbed:
/// - EDR: the registry reports SDR nits times the screen's current EDR headroom, so HDR
///   content appearing raises it. Readings are divided by the headroom, and the monitor
///   re-baselines silently while the headroom is moving.
/// - Idle dimming and display sleep: when the user comes back, macOS restores the level
///   right after the input that woke it. Returns towards the level the user left, or the
///   level the dim started from, are absorbed.
/// - Once the media-key tap has shown it sees brightness keys, a change that only follows
///   typing or pointer movement is not a key press, so it is not reported: brightness only
///   shows after a key.
///
/// While no built-in screen is online (clamshell mode) there is nothing to read: the panel
/// is off, and the HUD stays quiet even when the keys adjust an external display.
@MainActor
final class BrightnessMonitor {
    static let shared = BrightnessMonitor()

    static let pollInterval: Duration = .milliseconds(100)
    /// How far the level must move within `stepWindow` after a media key or click.
    static let fineStepThreshold: Double = 0.015
    /// How far it must move after other input, such as typing.
    static let coarseStepThreshold: Double = 0.05
    static let stepWindow: TimeInterval = 0.6
    static let keyOrPointerWindow: TimeInterval = 1.5
    static let anyInputWindow: TimeInterval = 2
    /// Readings closer than this are the same level.
    static let noiseFloor: Double = 0.0005
    /// A relative headroom change above this is an EDR transition (0.5 %).
    static let headroomChangeTolerance: Double = 0.005
    /// macOS ramps the EDR headroom over about 2 s; readings stay unreliable until it settles.
    static let headroomSettleWindow: TimeInterval = 2.5
    /// How close to the level the user left a return from idle dimming must stay. Below a
    /// Shift-Option step plus rounding, well below a full 1/16 key step.
    static let restoreTolerance: Double = 0.025
    /// At or below this the backlight is dark: display sleep, or the slider at zero.
    static let displayOffLevel: Double = 0.005
    /// A level that holds still for this long after the user is back is where they are now,
    /// even if it is not where they left it (auto-brightness moved it while they were away).
    static let presenceSettleTime: TimeInterval = 3
    /// A brightness key at the end of the slider does not move the level; the HUD shows it
    /// anyway when the level is within this of the end.
    static let clampMargin: Double = 0.005

    private static let logger = Logger(subsystem: "com.local.Notchy", category: "Brightness")

    /// Called with the new level, 0...1 on the slider's scale, after a user-sized change.
    var onUserChange: ((Double) -> Void)?
    private(set) var level: Double?
    /// The settled level while the user was present; idle dimming returns to it.
    private(set) var presenceLevel: Double?
    /// The screen was dimmed (or switched off) without the user; a return to
    /// `presenceLevel` or `dimmedFrom` is macOS undoing that, not a key press.
    private(set) var isIdleDimmed = false
    /// The highest level a dim (a quick fall with nobody around, or the backlight going
    /// dark) started from since the screen was last seen undimmed. macOS restores this
    /// level, which can differ from `presenceLevel` when auto-brightness moved it in between.
    private(set) var dimmedFrom: Double?
    /// The media-key tap has delivered a brightness key, so every key press reaches
    /// `brightnessKeyPressed`; cleared when the tap goes away for good.
    private(set) var seesBrightnessKeys = false

    private var pollTask: Task<Void, Never>?
    private var baseline: (level: Double, time: Date)?
    private var isTracking = false
    /// First steady poll, while idle-dimmed away from the presence level, with the user
    /// active again.
    private var userBackSince: Date?
    private var lastHeadroom: Double?
    private var headroomChangedAt: Date?
    private var lastBrightnessKey: Date?
    private let reader: @MainActor () -> BrightnessReading?
    private let inputRecency: @Sendable () -> InputRecency
    private let keyTargetsBuiltIn: @MainActor () -> Bool

    /// - Parameters:
    ///   - reader: the current reading, nil when there is none (no built-in screen online,
    ///     or no readable backlight).
    ///   - keyTargetsBuiltIn: whether a brightness key right now is for the built-in panel
    ///     rather than another screen; only consulted when the key cannot move the level.
    init(
        reader: @escaping @MainActor () -> BrightnessReading? = {
            BacklightRegistry.read(headroom: BuiltInScreen.currentHeadroom())
        },
        inputRecency: @escaping @Sendable () -> InputRecency = { InputRecency.current() },
        keyTargetsBuiltIn: @escaping @MainActor () -> Bool = { BuiltInScreen.isBrightnessKeyTarget() }
    ) {
        self.reader = reader
        self.inputRecency = inputRecency
        self.keyTargetsBuiltIn = keyTargetsBuiltIn
    }

    var isAvailable: Bool { reader() != nil }

    /// Starts polling from a fresh baseline; also how the level is re-read after display
    /// sleep or a screen change.
    func start() {
        guard pollTask == nil else { return }
        let now = Date()
        let reading = reader()
        level = reading?.level
        if let reading {
            // Compared with the headroom from before the stop, so a restart in the middle of
            // an EDR transition keeps its quiet period: AppKit can report the new headroom
            // while the backlight output is still ramping towards it.
            noteHeadroom(reading.headroom, at: now)
        }
        baseline = reading.map { ($0.level, now) }
        userBackSince = nil
        isTracking = false
        if reading == nil { Self.logger.info("No built-in screen or readable backlight; brightness HUD waits") }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                self.ingest(self.reader(), at: Date())
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isTracking = false
    }

    var isRunning: Bool { pollTask != nil }

    // MARK: Brightness keys

    /// A brightness key went down (repeats included), as seen by the media-key tap. Marks
    /// the key as the reason for the next change, and shows the HUD at once when the key
    /// cannot move the level because the slider is already at that end. Nothing shows while
    /// the monitor is stopped (display asleep, screen locked, HUD off), without a built-in
    /// screen, or when the key is more likely for another screen.
    func brightnessKeyPressed(_ direction: BrightnessKeyDirection, at time: Date = Date()) {
        lastBrightnessKey = time
        seesBrightnessKeys = true
        guard isRunning, let current = reader()?.level else { return }
        let atEnd = switch direction {
        case .up: current >= 1 - Self.clampMargin
        case .down: current <= Self.clampMargin
        }
        guard atEnd, keyTargetsBuiltIn() else { return }
        Self.logger.debug("Brightness key at the end of the slider (\(current, format: .fixed(precision: 3)))")
        onUserChange?(current)
    }

    /// The media-key tap is gone for good (Accessibility lost, or the HUD turned off), so
    /// key presses are no longer seen directly.
    func brightnessKeyTapDidStop() {
        seesBrightnessKeys = false
        lastBrightnessKey = nil
    }

    // MARK: Readings

    /// Feeds one slider-scale level read with `headroom`. Exposed for tests.
    func ingest(_ level: Double?, headroom: Double = 1, at time: Date) {
        ingest(level.map { BrightnessReading(level: $0, headroom: headroom) }, at: time)
    }

    /// Feeds one reading. Exposed for tests.
    func ingest(_ reading: BrightnessReading?, at time: Date) {
        guard let reading else { return }
        let value = reading.level
        let previous = level
        level = value
        noteHeadroom(reading.headroom, at: time)
        let headroomSettling = headroomChangedAt.map { time.timeIntervalSince($0) <= Self.headroomSettleWindow } ?? false

        guard let previous, abs(value - previous) > Self.noiseFloor else {
            settle(at: value, time: time, headroomSettling: headroomSettling)
            return
        }
        userBackSince = nil
        let tier = inputTier(at: time)
        if tier.isFine {
            clearIdleDimmed()
        } else if value <= Self.displayOffLevel {
            // The backlight went dark without a key or click: display sleep.
            markIdleDimmed(from: previous)
        }
        if headroomSettling && tier != .brightnessKey {
            // The nits and the headroom may have been read mid-ramp; start over once both
            // settle. A brightness key still wins: on XDR panels the headroom moves with
            // every step while HDR content is on screen.
            baseline = (value, time)
            isTracking = false
            return
        }
        if isTracking {
            // Already showing: follow every movement of the same gesture.
            onUserChange?(value)
            return
        }
        guard let start = baseline else {
            baseline = (value, time)
            return
        }
        if time.timeIntervalSince(start.time) > Self.stepWindow {
            // Too slow to be a key press so far; slide the window forward.
            baseline = (previous, time)
        }
        guard let start = baseline else { return }
        let moved = abs(value - start.level)
        let threshold: Double
        switch tier {
        case .brightnessKey, .keyOrPointer:
            threshold = Self.fineStepThreshold
        case .anyInput:
            if isIdleDimmed, isReturnFromIdle(from: previous, to: value) {
                // macOS undoing idle dimming right after the input that woke the user's
                // screen, possibly over several polls.
                Self.logger.debug("Absorbed brightness return \(previous, format: .fixed(precision: 3)) -> \(value, format: .fixed(precision: 3))")
                baseline = (value, time)
                return
            }
            if seesBrightnessKeys {
                // The tap sees every brightness key and none came: not a key press.
                baseline = (value, time)
                return
            }
            threshold = Self.coarseStepThreshold
        case .none:
            // Nobody touched anything, so no HUD.
            if moved >= Self.fineStepThreshold {
                if value < start.level {
                    // A quick fall: macOS dimming the idle screen before sleep. A rise, or a
                    // slow drift either way, is auto-brightness, which settles into the
                    // presence level as usual instead.
                    markIdleDimmed(from: start.level)
                }
                Self.logger.debug("Ignored brightness change without input")
                baseline = (value, time)
            }
            return
        }
        guard moved >= threshold else {
            Self.logger.debug("Brightness moved \(moved, format: .fixed(precision: 3)), below \(threshold, format: .fixed(precision: 3))")
            return
        }
        Self.logger.debug("Brightness \(start.level, format: .fixed(precision: 3)) -> \(value, format: .fixed(precision: 3))")
        clearIdleDimmed()
        isTracking = true
        onUserChange?(value)
    }

    /// The reading held still: the next movement starts a new measurement, and a steady
    /// level with the user around becomes the level idle dimming returns to.
    private func settle(at value: Double, time: Date, headroomSettling: Bool) {
        isTracking = false
        baseline = (value, time)
        if value <= Self.displayOffLevel {
            markIdleDimmed(from: nil)
            return
        }
        // Mid-EDR-ramp levels can be off by a step; do not remember them.
        guard !headroomSettling else { return }
        if isIdleDimmed && !isNearRestoreLevel(value) {
            // Counted from when the user is seen back, not from when the level stopped:
            // the first poll after their input usually comes before macOS starts restoring.
            guard inputRecency().sinceAnyInput <= Self.anyInputWindow else {
                userBackSince = nil
                return
            }
            guard let since = userBackSince else {
                userBackSince = time
                return
            }
            guard time.timeIntervalSince(since) >= Self.presenceSettleTime else { return }
        }
        clearIdleDimmed()
        presenceLevel = value
    }

    /// `from` is the level before the dim; the highest such level since the screen was last
    /// undimmed is the one macOS will restore.
    private func markIdleDimmed(from level: Double?) {
        isIdleDimmed = true
        guard let level, level > Self.displayOffLevel else { return }
        dimmedFrom = max(dimmedFrom ?? level, level)
    }

    private func clearIdleDimmed() {
        isIdleDimmed = false
        dimmedFrom = nil
        userBackSince = nil
    }

    /// Where macOS restores the screen to when the user comes back: the higher of the level
    /// they left and the level the dim started from. Nil when neither is known.
    private var restoreLevel: Double? {
        [presenceLevel, dimmedFrom].compactMap { $0 }.max()
    }

    private func isNearRestoreLevel(_ value: Double) -> Bool {
        let targets = [presenceLevel, dimmedFrom].compactMap { $0 }
        return targets.isEmpty || targets.contains { abs(value - $0) <= Self.restoreTolerance }
    }

    /// While idle-dimmed, a change after mere typing or pointer movement is macOS restoring
    /// the screen when it rises from dark, falls (the dim ramp finishing as the user comes
    /// back), or rises no further than the level it restores to.
    private func isReturnFromIdle(from previous: Double, to value: Double) -> Bool {
        if previous <= Self.displayOffLevel || value < previous { return true }
        guard let restoreLevel else { return true }
        return value <= restoreLevel + Self.restoreTolerance
    }

    private func noteHeadroom(_ headroom: Double, at time: Date) {
        defer { lastHeadroom = headroom }
        guard let lastHeadroom, lastHeadroom > 0 else { return }
        if abs(headroom - lastHeadroom) / lastHeadroom > Self.headroomChangeTolerance {
            Self.logger.debug("EDR headroom \(lastHeadroom, format: .fixed(precision: 3)) -> \(headroom, format: .fixed(precision: 3))")
            headroomChangedAt = time
        }
    }

    /// What most plausibly explains a change at `time`, strongest first.
    private func inputTier(at time: Date) -> InputTier {
        if let lastBrightnessKey, abs(time.timeIntervalSince(lastBrightnessKey)) <= Self.keyOrPointerWindow {
            return .brightnessKey
        }
        let recency = inputRecency()
        if recency.sinceKeyOrPointer <= Self.keyOrPointerWindow { return .keyOrPointer }
        if recency.sinceAnyInput <= Self.anyInputWindow { return .anyInput }
        return .none
    }

    private enum InputTier {
        /// The media-key tap saw a brightness key.
        case brightnessKey
        /// A media key or pointer press (NX_SYSDEFINED recency is also bumped by clicks).
        case keyOrPointer
        /// Typing or pointer movement only.
        case anyInput
        /// No input at all.
        case none

        var isFine: Bool { self == .brightnessKey || self == .keyOrPointer }
    }
}

/// One brightness sample.
struct BrightnessReading: Sendable, Equatable {
    /// 0...1 on the brightness slider's scale.
    var level: Double
    /// The built-in screen's EDR headroom the level was converted with; 1 when SDR only.
    var headroom: Double = 1
}

/// How long ago the user last gave input, from the HID event state (public, no permission).
struct InputRecency: Sendable, Equatable {
    /// A media key (brightness, volume) or a click or drag, as on the Control Center slider.
    var sinceKeyOrPointer: TimeInterval
    /// Any key, pointer or trackpad input.
    var sinceAnyInput: TimeInterval

    static func current() -> InputRecency {
        func since(_ raw: UInt32) -> TimeInterval {
            guard let type = CGEventType(rawValue: raw) else { return .infinity }
            return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
        }
        // 14 is NX_SYSDEFINED, the event media keys arrive as; ~0 is kCGAnyInputEventType.
        let keyOrPointer = [
            since(14),
            since(CGEventType.leftMouseDown.rawValue),
            since(CGEventType.leftMouseDragged.rawValue),
        ].min() ?? .infinity
        return InputRecency(sinceKeyOrPointer: keyOrPointer, sinceAnyInput: since(~0))
    }
}

/// Converts the panel's SDR light output back to the brightness slider's 0...1 scale.
///
/// Measured on a built-in Apple silicon panel by stepping the slider through its 16 key
/// steps with no HDR content on screen: the full slider is the panel's backlight cap
/// (`BLNitsCap`), above half brightness each step multiplies the output by 1.2, below half
/// by about 1.835, and zero is off.
enum BrightnessCurve {
    static let upperStepRatio = 1.2
    static let lowerStepRatio = 1.835
    static let stepsPerSlider = 16.0
    /// Full-slider SDR output when the panel does not publish its cap.
    static let defaultFullNits = 600.0

    static func fullNits(backlightCapNits: Double?) -> Double {
        guard let cap = backlightCapNits, cap > 0 else { return defaultFullNits }
        return cap
    }

    /// The registry's output is SDR nits times the current EDR headroom.
    static func sliderLevel(physicalNits: Double, headroom: Double, backlightCapNits: Double?) -> Double {
        sliderLevel(
            nits: physicalNits / max(1, headroom),
            fullNits: fullNits(backlightCapNits: backlightCapNits)
        )
    }

    static func sliderLevel(nits: Double, fullNits: Double) -> Double {
        guard nits > 0, fullNits > 0 else { return 0 }
        let halfNits = fullNits / pow(upperStepRatio, stepsPerSlider / 2)
        let level: Double
        if nits >= halfNits {
            level = 1 + log(nits / fullNits) / (stepsPerSlider * log(upperStepRatio))
        } else {
            level = 0.5 + log(nits / halfNits) / (stepsPerSlider * log(lowerStepRatio))
        }
        return min(1, max(0, level))
    }
}

/// Reads the built-in display's brightness from the I/O Registry.
enum BacklightRegistry {
    /// Apple silicon: the built-in panel's framebuffer publishes its output in 16.16 nits,
    /// scaled by `headroom` (the built-in screen's current EDR headroom, read by the caller
    /// on the main actor). Intel: the display connection publishes the slider level directly.
    ///
    /// A nil `headroom` means no built-in screen is online (clamshell mode). The panel's
    /// framebuffer stays in the registry with the lid closed, but its level then describes
    /// a panel that is off, so there is no reading.
    static func read(headroom: Double?) -> BrightnessReading? {
        guard let headroom else { return nil }
        if let reading = framebufferReading() {
            let level = BrightnessCurve.sliderLevel(
                physicalNits: reading.nits,
                headroom: headroom,
                backlightCapNits: reading.capNits
            )
            return BrightnessReading(level: level, headroom: headroom)
        }
        // The Intel level is not scaled by EDR; a fixed headroom keeps the monitor from
        // waiting out headroom changes that do not affect it.
        return displayConnectLevel().map { BrightnessReading(level: $0, headroom: 1) }
    }

    /// The built-in panel is the framebuffer that is not marked external and has a
    /// brightness scale.
    static func framebufferReading() -> (nits: Double, capNits: Double?)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator)
            == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if (property("external") as? Bool) == true { continue }
            guard property("Brightness_Scale") != nil,
                  let level = (property("IOMFBBrightnessLevel") as? NSNumber)?.doubleValue
            else { continue }
            let cap = (property("BLNitsCap") as? NSNumber)?.doubleValue
            return (fixedPointNits(level), cap.map(fixedPointNits))
        }
        return nil
    }

    static func fixedPointNits(_ value: Double) -> Double { value / 65536 }

    private static func displayConnectLevel() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        else { return nil }
        return normalized(raw["brightness"])
    }

    static func normalized(_ entry: Any?) -> Double? {
        guard let parameters = entry as? [String: Any],
              let value = (parameters["value"] as? NSNumber)?.doubleValue,
              let maximum = (parameters["max"] as? NSNumber)?.doubleValue
        else { return nil }
        let minimum = (parameters["min"] as? NSNumber)?.doubleValue ?? 0
        guard maximum > minimum else { return nil }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }
}
