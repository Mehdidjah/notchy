import AppKit
import Foundation
import Testing
@testable import Notchy

@MainActor
struct ColorPickerTests {
    // MARK: Formatting

    @Test
    func hexRoundsChannelsAndAppendsAlphaOnlyWhenTranslucent() {
        let orange = PickedColor(red: 1, green: 128.0 / 255.0, blue: 0)
        #expect(orange.hexString == "#FF8000")
        #expect(orange.isOpaque)

        let translucent = PickedColor(red: 1, green: 128.0 / 255.0, blue: 0, alpha: 0.5)
        #expect(translucent.hexString == "#FF800080", "0.5 * 255 = 127.5 rounds to 0x80")

        let nearlyHalf = PickedColor(red: 0.5019607, green: 0.5019608, blue: 0)
        #expect(nearlyHalf.hexString == "#808000", "float noise around 128 must not truncate to 127")
    }

    @Test
    func rgbAndRgbaUseByteChannelsAndTwoDecimalAlpha() {
        let color = PickedColor(red: 1, green: 128.0 / 255.0, blue: 0, alpha: 0.5)
        #expect(color.rgbString == "rgb(255, 128, 0)")
        #expect(color.rgbaString == "rgba(255, 128, 0, 0.50)")
    }

    @Test
    func hslAndHsvMatchCssConventions() {
        let azure = PickedColor(red: 0, green: 128.0 / 255.0, blue: 1)
        #expect(azure.hslString == "hsl(210, 100%, 50%)")
        #expect(azure.hslaString == "hsla(210, 100%, 50%, 1.00)")
        #expect(azure.hsvString == "hsv(210, 100%, 100%)")

        let red = PickedColor(red: 1, green: 0, blue: 0)
        #expect(red.hslString == "hsl(0, 100%, 50%)")
        #expect(red.hsvString == "hsv(0, 100%, 100%)")

        let grey = PickedColor(red: 0.5, green: 0.5, blue: 0.5)
        #expect(grey.hslString == "hsl(0, 0%, 50%)")
        #expect(grey.hsvString == "hsv(0, 0%, 50%)")

        let magentaish = PickedColor(red: 1, green: 0, blue: 0.5)
        #expect(magentaish.hsl.hue == 330, "hues from the red sector wrap into 0..<360")
    }

    @Test
    func codeLiteralsUseThreeDecimals() {
        let color = PickedColor(red: 1, green: 128.0 / 255.0, blue: 0)
        #expect(color.swiftUIString == "Color(red: 1.000, green: 0.502, blue: 0.000, opacity: 1.000)")
        #expect(color.uiColorString == "UIColor(red: 1.000, green: 0.502, blue: 0.000, alpha: 1.000)")
    }

    @Test
    func everyFormatProducesAValue() {
        let color = PickedColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        for format in PickedColorFormat.allCases {
            let value = color.formatted(as: format)
            #expect(!value.isEmpty)
            #expect(!format.displayName.isEmpty)
        }
        #expect(color.formatted(as: .hex) == color.hexString)
        #expect(color.formatted(as: .uiColor) == color.uiColorString)
    }

    @Test
    func componentsAreClampedAndWideGamutColorsConvertToSRGB() {
        let wild = PickedColor(red: 2, green: -1, blue: .nan)
        #expect(wild.red == 1)
        #expect(wild.green == 0)
        #expect(wild.blue == 0)

        let p3Red = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let converted = PickedColor(nsColor: p3Red)
        #expect(converted != nil)
        #expect(converted?.hexString == "#FF0000")

        let srgb = PickedColor(nsColor: NSColor(srgbRed: 0, green: 128.0 / 255.0, blue: 1, alpha: 1))
        #expect(srgb?.hexString == "#0080FF")
    }

    @Test
    func relativeAgeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func color(secondsAgo: TimeInterval) -> PickedColor {
            PickedColor(red: 0, green: 0, blue: 0, pickedAt: now.addingTimeInterval(-secondsAgo))
        }
        #expect(color(secondsAgo: 5).relativeAge(now: now) == "Just now")
        #expect(color(secondsAgo: 5 * 60).relativeAge(now: now) == "5m ago")
        #expect(color(secondsAgo: 3 * 3_600).relativeAge(now: now) == "3h ago")
        #expect(color(secondsAgo: 2 * 86_400).relativeAge(now: now) == "2d ago")
        #expect(color(secondsAgo: -30).relativeAge(now: now) == "Just now", "clock skew never reads as negative")
    }

    @Test
    func looksLikeComparesVisibleChannelsNotIdentity() {
        let first = PickedColor(red: 0.5, green: 0.5, blue: 0.5)
        let second = PickedColor(red: 0.5000001, green: 0.5, blue: 0.5)
        let other = PickedColor(red: 0.6, green: 0.5, blue: 0.5)
        #expect(first.id != second.id)
        #expect(first.looksLike(second))
        #expect(!first.looksLike(other))
    }

    // MARK: Settings

    @Test
    func settingsPersistUnderPrefixedKeysAndSanitiseHistorySize() {
        let harness = TestHarness()
        defer { harness.tearDown() }

        let settings = ColorPickerSettings(defaults: harness.defaults)
        #expect(settings.isEnabled)
        #expect(settings.showHeaderButton)
        #expect(settings.defaultFormat == .hex)
        #expect(settings.historySize == ColorPickerSettings.defaultHistorySize)
        #expect(settings.showAllFormats)

        settings.defaultFormat = .rgb
        settings.historySize = 20
        settings.showAllFormats = false
        #expect(harness.defaults.string(forKey: "colorPicker.defaultFormat") == "rgb")
        #expect(harness.defaults.integer(forKey: "colorPicker.historySize") == 20)
        #expect(harness.defaults.bool(forKey: "colorPicker.showAllFormats") == false)

        harness.defaults.set(7, forKey: "colorPicker.historySize")
        let reloaded = ColorPickerSettings(defaults: harness.defaults)
        #expect(reloaded.defaultFormat == .rgb)
        #expect(reloaded.historySize == ColorPickerSettings.defaultHistorySize, "sizes outside the offered choices fall back")
    }

    // MARK: Service

    @Test
    func pickingCopiesDefaultFormatRecordsHistoryAndReportsHex() async {
        let harness = TestHarness()
        defer { harness.tearDown() }
        harness.sampler.result = NSColor(srgbRed: 0, green: 128.0 / 255.0, blue: 1, alpha: 1)
        let service = harness.makeService()
        var reportedHex: [String] = []
        var pickedColors: [PickedColor] = []
        service.onColorCopied = { reportedHex.append($0) }
        service.onColorPicked = { pickedColors.append($0) }

        service.pick()
        #expect(service.isPicking)
        await harness.sampler.waitUntilSampled()
        await Task.yield()
        await Task.yield()

        #expect(!service.isPicking)
        #expect(service.history.map(\.hexString) == ["#0080FF"])
        #expect(service.lastPickedColor?.hexString == "#0080FF")
        #expect(service.lastCopiedValue == "#0080FF")
        #expect(harness.pasteboard.copiedValues == ["#0080FF"])
        #expect(reportedHex == ["#0080FF"])
        #expect(pickedColors.count == 1)
        #expect(harness.haptics.count == 1)
        #expect(service.isShowingPickedFeedback)
    }

    @Test
    func pickingHonoursDefaultFormatSetting() async {
        let harness = TestHarness()
        defer { harness.tearDown() }
        harness.sampler.result = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let service = harness.makeService()
        service.settings.defaultFormat = .rgb

        service.pick()
        await harness.sampler.waitUntilSampled()
        await Task.yield()
        await Task.yield()

        #expect(harness.pasteboard.copiedValues == ["rgb(255, 0, 0)"])
        #expect(service.lastCopiedValue == "rgb(255, 0, 0)")
    }

    @Test
    func cancelledLoupeLeavesEverythingUntouched() async {
        let harness = TestHarness()
        defer { harness.tearDown() }
        harness.sampler.result = nil
        let service = harness.makeService()

        service.pick()
        await harness.sampler.waitUntilSampled()
        await Task.yield()
        await Task.yield()

        #expect(!service.isPicking)
        #expect(service.history.isEmpty)
        #expect(harness.pasteboard.copiedValues.isEmpty)
        #expect(harness.haptics.count == 0)
        #expect(!service.isShowingPickedFeedback)
    }

    @Test
    func pickIsIgnoredWhileDisabledOrAlreadyPicking() async {
        let harness = TestHarness()
        defer { harness.tearDown() }
        harness.sampler.result = NSColor.white
        let service = harness.makeService()

        service.settings.isEnabled = false
        service.pick()
        #expect(!service.isPicking)
        #expect(harness.sampler.sampleCount == 0)

        service.settings.isEnabled = true
        harness.sampler.holdOpen = true
        service.pick()
        service.pick()
        #expect(service.isPicking)
        await harness.sampler.waitUntilSampled()
        #expect(harness.sampler.sampleCount == 1)
        harness.sampler.release()
        await Task.yield()
        await Task.yield()
        #expect(!service.isPicking)
    }

    @Test
    func historyIsNewestFirstDedupedAndCapped() {
        let harness = TestHarness()
        defer { harness.tearDown() }
        let service = harness.makeService()

        for index in 0..<60 {
            service.accept(PickedColor(red: Double(index) / 255, green: 0, blue: 0))
        }
        #expect(service.history.count == ColorPickerService.maximumStoredColors)
        #expect(service.history.first?.channels.red == 59)
        #expect(service.history.last?.channels.red == 10)

        service.accept(PickedColor(red: 30.0 / 255, green: 0, blue: 0))
        #expect(service.history.count == ColorPickerService.maximumStoredColors, "a re-pick moves, it does not add")
        #expect(service.history.first?.channels.red == 30)
        #expect(service.history.filter { $0.channels.red == 30 }.count == 1)
    }

    @Test
    func historyPersistsAcrossInstancesAndClears() {
        let harness = TestHarness()
        defer { harness.tearDown() }
        let service = harness.makeService()
        let teal = PickedColor(red: 0, green: 0.5, blue: 0.5)
        let plum = PickedColor(red: 0.5, green: 0, blue: 0.5)
        service.accept(teal)
        service.accept(plum)

        let reloaded = harness.makeService()
        #expect(reloaded.history.map(\.id) == [plum.id, teal.id])
        #expect(harness.defaults.data(forKey: "colorPicker.history") != nil)

        reloaded.remove(plum)
        #expect(reloaded.history.map(\.id) == [teal.id])

        reloaded.clearHistory()
        #expect(reloaded.history.isEmpty)
        #expect(harness.makeService().history.isEmpty)
    }

    @Test
    func recentColorsFollowTheHistorySizeSetting() {
        let harness = TestHarness()
        defer { harness.tearDown() }
        let service = harness.makeService()
        for index in 0..<30 {
            service.accept(PickedColor(red: 0, green: Double(index) / 255, blue: 0))
        }
        service.settings.historySize = 5
        #expect(service.recentColors.count == 5)
        service.settings.historySize = 20
        #expect(service.recentColors.count == 20)
        #expect(service.recentColors.first?.id == service.history.first?.id)
    }

    @Test
    func copyingAFormatWritesThatFormatButReportsHex() {
        let harness = TestHarness()
        defer { harness.tearDown() }
        let service = harness.makeService()
        var reported: [String] = []
        service.onColorCopied = { reported.append($0) }
        let color = PickedColor(red: 1, green: 128.0 / 255.0, blue: 0)

        #expect(service.copy(color, as: .hsl))
        #expect(harness.pasteboard.copiedValues == ["hsl(30, 100%, 50%)"])
        #expect(service.lastCopiedValue == "hsl(30, 100%, 50%)")
        #expect(reported == ["#FF8000"])
        #expect(harness.haptics.count == 0, "format rows copy silently")

        #expect(service.copy(color, as: .hex, haptic: true))
        #expect(harness.haptics.count == 1)

        service.hapticsEnabled = { false }
        #expect(service.copy(color, as: .hex, haptic: true))
        #expect(harness.haptics.count == 1, "the island's haptics preference is honoured")

        harness.pasteboard.succeeds = false
        #expect(!service.copy(color, as: .rgb))
        #expect(reported.count == 3, "a failed write reports nothing")
        #expect(service.lastCopiedValue == "#FF8000")
    }

    @Test
    func popoverPresentationIsReportedOnceperChange() {
        let harness = TestHarness()
        defer { harness.tearDown() }
        let service = harness.makeService()
        var changes: [Bool] = []
        service.onPopoverPresentationChanged = { changes.append($0) }

        service.setPopoverPresented(true)
        service.setPopoverPresented(true)
        service.setPopoverPresented(false)
        #expect(service.isPopoverPresented == false)
        #expect(changes == [true, false])
    }
}

// MARK: - Doubles

@MainActor
private final class TestHarness {
    let suiteName = "ColorPickerTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let sampler = ColorSamplerStub()
    let pasteboard = ColorPasteboardSpy()
    let haptics = ColorHapticSpy()

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func makeService() -> ColorPickerService {
        ColorPickerService(
            settings: ColorPickerSettings(defaults: defaults),
            defaults: defaults,
            sampler: sampler,
            pasteboard: pasteboard,
            haptics: haptics
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class ColorSamplerStub: ScreenColorSampling {
    var result: NSColor?
    var sampleCount = 0
    /// When true the stub stays "on screen" until `release()` is called.
    var holdOpen = false
    private var sampledContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func sampleColor() async -> NSColor? {
        sampleCount += 1
        let waiters = sampledContinuations
        sampledContinuations.removeAll()
        for waiter in waiters { waiter.resume() }
        if holdOpen {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return result
    }

    func waitUntilSampled() async {
        guard sampleCount == 0 else { return }
        await withCheckedContinuation { continuation in
            sampledContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class ColorPasteboardSpy: PasteboardWriting {
    var copiedValues: [String] = []
    var succeeds = true

    @discardableResult
    func copy(_ value: String) -> Bool {
        guard succeeds else { return false }
        copiedValues.append(value)
        return true
    }
}

@MainActor
private final class ColorHapticSpy: HapticFeedbackPerforming {
    var count = 0
    func perform() { count += 1 }
}
