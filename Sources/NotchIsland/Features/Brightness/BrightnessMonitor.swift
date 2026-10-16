import CoreGraphics
import Foundation
import IOKit
import os

/// Watches the built-in display's brightness so the island can show Atoll's brightness HUD.
/// There is no public API for the brightness slider, so the level is read from the I/O
/// Registry (a public read that needs no permission) and converted back to the slider's
/// scale with `BrightnessCurve`.
///
/// Brightness keys move the slider by 1/16 (1/64 with Shift-Option) within a fraction of a
/// second, while auto-brightness drifts slowly and macOS dims the screen on its own before
/// sleep, after a stretch without input. A change is reported only when it is quick and
/// follows input: a media key or pointer press allows fine steps, other input only full
/// ones, and no input at all never shows the HUD.
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

    private static let logger = Logger(subsystem: "com.local.NotchIsland", category: "Brightness")

    /// Called with the new level, 0...1 on the slider's scale, after a user-sized change.
    var onUserChange: ((Double) -> Void)?
    private(set) var level: Double?

    private var pollTask: Task<Void, Never>?
    private var baseline: (level: Double, time: Date)?
    private var isTracking = false
    private let reader: @Sendable () -> Double?
    private let inputRecency: @Sendable () -> InputRecency

    init(
        reader: @escaping @Sendable () -> Double? = { BacklightRegistry.readLevel() },
        inputRecency: @escaping @Sendable () -> InputRecency = { InputRecency.current() }
    ) {
        self.reader = reader
        self.inputRecency = inputRecency
    }

    var isAvailable: Bool { reader() != nil }

    func start() {
        guard pollTask == nil else { return }
        level = reader()
        baseline = level.map { ($0, Date()) }
        if level == nil { Self.logger.info("No readable built-in backlight; brightness HUD stays off") }
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

    /// Feeds one reading. Exposed for tests.
    func ingest(_ reading: Double?, at time: Date) {
        guard let reading else { return }
        let previous = level
        level = reading
        guard let previous, abs(reading - previous) > 0.0005 else {
            // Settled: the next movement starts a new measurement.
            if isTracking, let previous, abs(reading - previous) <= 0.0005 { isTracking = false }
            if !isTracking { baseline = (reading, time) }
            return
        }
        if isTracking {
            // Already showing: follow every movement of the same gesture.
            onUserChange?(reading)
            return
        }
        guard let start = baseline else {
            baseline = (reading, time)
            return
        }
        if time.timeIntervalSince(start.time) > Self.stepWindow {
            // Too slow to be a key press so far; slide the window forward.
            baseline = (previous, time)
        }
        guard let start = baseline else { return }
        let moved = abs(reading - start.level)
        let recency = inputRecency()
        let threshold: Double
        if recency.sinceKeyOrPointer <= Self.keyOrPointerWindow {
            threshold = Self.fineStepThreshold
        } else if recency.sinceAnyInput <= Self.anyInputWindow {
            threshold = Self.coarseStepThreshold
        } else {
            // Idle dimming before sleep: nobody touched anything, so no HUD.
            if moved >= Self.fineStepThreshold {
                Self.logger.debug("Ignored brightness change without input (\(recency.sinceAnyInput, format: .fixed(precision: 1)) s idle)")
                baseline = (reading, time)
            }
            return
        }
        guard moved >= threshold else {
            Self.logger.debug("Brightness moved \(moved, format: .fixed(precision: 3)), below \(threshold, format: .fixed(precision: 3))")
            return
        }
        Self.logger.debug("Brightness \(start.level, format: .fixed(precision: 3)) -> \(reading, format: .fixed(precision: 3))")
        isTracking = true
        onUserChange?(reading)
    }
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

/// Converts the panel's light output back to the brightness slider's 0...1 scale.
///
/// Measured on a built-in Apple silicon panel by stepping the slider through its 16 key
/// steps: above half brightness each step multiplies the output by 1.2, below half by about
/// 1.835, and the full slider sits one 1.2 step above the panel's backlight cap.
enum BrightnessCurve {
    static let upperStepRatio = 1.2
    static let lowerStepRatio = 1.835
    static let stepsPerSlider = 16.0
    /// Full-slider output when the panel does not publish its cap.
    static let defaultFullNits = 720.0

    static func fullNits(backlightCapNits: Double?) -> Double {
        guard let cap = backlightCapNits, cap > 0 else { return defaultFullNits }
        return cap * upperStepRatio
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
    /// Apple silicon: the built-in panel's framebuffer publishes its output in 16.16 nits.
    /// Intel: the display connection publishes the slider level directly.
    static func readLevel() -> Double? {
        if let reading = framebufferReading() {
            return BrightnessCurve.sliderLevel(
                nits: reading.nits,
                fullNits: BrightnessCurve.fullNits(backlightCapNits: reading.capNits)
            )
        }
        return displayConnectLevel()
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
