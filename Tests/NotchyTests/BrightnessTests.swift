import Foundation
import Testing
@testable import Notchy

@MainActor
struct BrightnessTests {
    nonisolated private static let afterKeyPress = InputRecency(sinceKeyOrPointer: 0.2, sinceAnyInput: 0.2)
    nonisolated private static let afterTyping = InputRecency(sinceKeyOrPointer: 30, sinceAnyInput: 0.3)
    nonisolated private static let idle = InputRecency(sinceKeyOrPointer: 30, sinceAnyInput: 30)

    @Test
    func keyPressStepIsReportedButAutoBrightnessDriftIsNot() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.afterTyping })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let start = Date()

        // Auto-brightness: 0.5 -> 0.53 over 3 s in tiny steps.
        for i in 0...30 {
            monitor.ingest(0.5 + Double(i) * 0.001, at: start.addingTimeInterval(Double(i) * 0.1))
        }
        #expect(reported.isEmpty)

        // Settle, then a key press ramps 1/16 within 0.3 s.
        let t = start.addingTimeInterval(4)
        monitor.ingest(0.53, at: t)
        monitor.ingest(0.53, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.56, at: t.addingTimeInterval(0.2))
        monitor.ingest(0.5925, at: t.addingTimeInterval(0.3))
        #expect(reported == [0.5925], "a full step shows once it has moved past the coarse threshold")

        // The same gesture keeps reporting until the level settles.
        monitor.ingest(0.6, at: t.addingTimeInterval(0.4))
        #expect(reported.last == 0.6)
    }

    @Test
    func fineStepShowsRightAfterAMediaKey() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.afterKeyPress })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let t = Date()
        monitor.ingest(0.5, at: t)
        monitor.ingest(0.5, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.5156, at: t.addingTimeInterval(0.2))
        #expect(reported == [0.5156], "a 1/64 Shift-Option step")
    }

    @Test
    func idleDimmingWithoutInputIsIgnored() {
        let monitor = BrightnessMonitor(reader: { nil }, inputRecency: { Self.idle })
        var reported: [Double] = []
        monitor.onUserChange = { reported.append($0) }
        let t = Date()
        monitor.ingest(0.8, at: t)
        monitor.ingest(0.6, at: t.addingTimeInterval(0.1))
        monitor.ingest(0.4, at: t.addingTimeInterval(0.2))
        #expect(reported.isEmpty)
    }

    /// Points measured on the built-in panel (slider -> nits, backlight cap 600 nits).
    @Test(arguments: [
        (0.0625, 2.400), (0.125, 4.403), (0.25, 14.824), (0.3125, 27.199),
        (0.5625, 201.517), (0.75, 347.793), (0.875, 500.411), (1.0, 720.0),
    ])
    func curveMapsMeasuredOutputBackToTheSlider(slider: Double, nits: Double) {
        let full = BrightnessCurve.fullNits(backlightCapNits: 600)
        #expect(full == 720)
        #expect(abs(BrightnessCurve.sliderLevel(nits: nits, fullNits: full) - slider) < 0.01)
    }

    @Test
    func curveClampsAndHandlesOff() {
        #expect(BrightnessCurve.sliderLevel(nits: 0, fullNits: 720) == 0)
        #expect(BrightnessCurve.sliderLevel(nits: 0.01, fullNits: 720) == 0)
        #expect(BrightnessCurve.sliderLevel(nits: 900, fullNits: 720) == 1)
        #expect(BrightnessCurve.fullNits(backlightCapNits: nil) == BrightnessCurve.defaultFullNits)
        #expect(BacklightRegistry.fixedPointNits(22_792_960) > 347 && BacklightRegistry.fixedPointNits(22_792_960) < 348)
    }

    @Test
    func hudUsesAtollsSunGlyphsAndALevelPeek() {
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.3) == "sun.min.fill")
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.6) == "sun.min.fill")
        #expect(SystemHUDPresenter.brightnessSymbolName(for: 0.61) == "sun.max.fill")
        let peek = SystemHUDPresenter.standardSneakPeek(kind: .brightness, level: 0, isBluetooth: false)
        #expect(peek.kind == .brightness)
        #expect(peek.level == 0, "brightness has no muted state")
    }

    @Test
    func registryValuesAreNormalized() {
        #expect(BacklightRegistry.normalized(["min": 0, "max": 65536, "value": 32768]) == 0.5)
        #expect(BacklightRegistry.normalized(["max": 0, "value": 1]) == nil)
        #expect(BacklightRegistry.normalized("nope") == nil)
        let live = BacklightRegistry.readLevel()
        #expect(live == nil || (0...1).contains(live!))
    }
}
