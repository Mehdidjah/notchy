import Foundation
import Testing
@testable import NotchIsland

@MainActor
struct NotchViewModelTests {
    @Test
    func categoryAndSearchFiltersCompose() {
        let model = NotchViewModel(items: Clip.debugPreviewItems)

        model.selectCategory(.colors)
        #expect(model.filteredItems.map(\.value) == ["#0080FF"])

        model.selectCategory(.history)
        model.query = "Rocket Drive"
        #expect(model.filteredItems.count == 1)
        #expect(model.filteredItems.first?.detail.contains("Chrome") == true)
    }

    @Test
    func selectingHistoryItemWritesThroughPasteboardBoundary() {
        let pasteboard = PasteboardSpy()
        let model = NotchViewModel(
            items: Clip.debugPreviewItems,
            pasteboardService: pasteboard
        )
        let item = Clip.debugPreviewItems[0]

        model.copy(item)

        #expect(pasteboard.copiedValues == [item.value])
        #expect(model.copiedItemID == item.id)
    }

    @Test
    func existingInstallMigratesToHalfSecondHoverTiming() {
        let suiteName = "NotchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(120, forKey: "notch.hoverDelayMilliseconds")
        defaults.set(420, forKey: "notch.closeDelayMilliseconds")

        let settings = UserSettings(defaults: defaults)

        #expect(settings.hoverDelayMilliseconds == 500)
        #expect(settings.closeDelayMilliseconds == 500)
    }

    @Test
    func hoverRequiresDwellAndClosingReentryRequiresANewDwell() async {
        let suiteName = "NotchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = UserSettings(defaults: defaults)
        settings.hoverDelayMilliseconds = 80
        settings.closeDelayMilliseconds = 80
        let model = NotchViewModel(settings: settings)

        model.pointerEntered()
        #expect(model.state == .hoverArmed)
        try? await Task.sleep(for: .milliseconds(30))
        model.pointerExited()
        try? await Task.sleep(for: .milliseconds(90))
        #expect(model.state == .idle)

        model.pointerEntered()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .expanded)

        model.pointerExited()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.state == .expanded)
        try? await Task.sleep(for: .milliseconds(70))
        #expect(model.state == .closing)

        model.pointerEntered()
        #expect(model.state == .hoverArmed)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.state == .hoverArmed)
        model.pointerExited()
        #expect(model.state == .idle)
    }

    @Test
    func closingOnlyKeepsThePhysicalNotchTriggerInteractive() {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            topInset: 32,
            hardwareNotchWidth: 185,
            isHardwareNotch: true
        )

        let metrics = NotchGeometryResolver.metrics(
            state: .closing,
            geometry: geometry,
            preferredExpandedWidth: 840
        )

        #expect(metrics.interactiveSize.width == geometry.triggerWidth)
        #expect(metrics.interactiveSize.height == geometry.triggerHeight)
        #expect(metrics.interactiveSize.width < 840)
    }

    @Test
    func collapsedSurfaceMatchesHardwareNotchButKeepsALargerInvisibleSensor() {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            topInset: 32,
            hardwareNotchWidth: 185,
            isHardwareNotch: true
        )

        let metrics = NotchGeometryResolver.metrics(
            state: .idle,
            geometry: geometry,
            preferredExpandedWidth: 840
        )

        #expect(metrics.renderedSize == CGSize(width: 183, height: 32))
        #expect(metrics.interactiveSize.width > metrics.renderedSize.width)
        #expect(metrics.interactiveSize.height > metrics.renderedSize.height)
    }
}

@MainActor
private final class PasteboardSpy: PasteboardWriting {
    private(set) var copiedValues: [String] = []

    func copy(_ value: String) -> Bool {
        copiedValues.append(value)
        return true
    }
}
