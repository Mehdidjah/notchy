import AppKit
import Combine
import SwiftUI
import Foundation
import Testing
@testable import NotchIsland

@MainActor
struct NotchViewModelTests {
    @Test
    func categoryAndSearchFiltersCompose() {
        let model = NotchViewModel(items: Clip.debugPreviewItems, haptics: HapticSpy())

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
            pasteboardService: pasteboard,
            haptics: HapticSpy()
        )
        let item = Clip.debugPreviewItems[0]

        model.copy(item)

        #expect(pasteboard.copiedValues == [item.value])
        #expect(model.copiedItemID == item.id)
    }

    @Test
    func existingInstallMigratesToCurrentHoverTiming() {
        let suiteName = "NotchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(120, forKey: "notch.hoverDelayMilliseconds")
        defaults.set(420, forKey: "notch.closeDelayMilliseconds")
        defaults.set(1, forKey: "notch.hoverTimingVersion")

        let settings = UserSettings(defaults: defaults)

        #expect(settings.hoverDelayMilliseconds == NotchInteractionDefaults.hoverDelayMilliseconds)
        #expect(settings.closeDelayMilliseconds == NotchInteractionDefaults.closeDelayMilliseconds)
        #expect(defaults.integer(forKey: "notch.hoverTimingVersion") == NotchInteractionDefaults.hoverTimingVersion)
    }

    @Test
    func hoverRequiresDwellAndClosingReentryRequiresANewDwell() async {
        let settings = makeSettings(hoverDelay: 80, closeDelay: 80)
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)

        model.pointerEntered()
        #expect(model.state == .hoverArmed)
        #expect(model.isHovering)
        #expect(model.showsHoverSwell)
        try? await Task.sleep(for: .milliseconds(30))
        model.pointerExited()
        #expect(model.state == .hoverArmed, "a brief exit keeps the swell for the grace period")
        #expect(await eventually { model.state == .idle })
        #expect(!model.isHovering)

        model.pointerEntered()
        #expect(await eventually { model.state == .expanded })
        #expect(!model.showsHoverSwell)

        model.pointerExited()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.state == .expanded)
        #expect(await eventually { model.state == .closing })
        #expect(!model.isHovering)

        model.pointerEntered()
        #expect(model.state == .hoverArmed)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.state == .hoverArmed)
        model.pointerExited()
        #expect(await eventually { model.state == .idle })
    }

    @Test
    func briefExitDuringArmedHoverDoesNotCancelTheDwell() async {
        let settings = makeSettings(hoverDelay: 60, closeDelay: 80)
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)

        model.pointerEntered()
        try? await Task.sleep(for: .milliseconds(20))
        model.pointerExited()
        try? await Task.sleep(for: .milliseconds(20))
        model.pointerEntered()
        #expect(model.state == .hoverArmed)
        #expect(await eventually { model.state == .expanded })
    }

    @Test
    func leavingDuringTheCloseAnimationStillReachesIdle() async {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 40)
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)
        model.closeAnimationDuration = .milliseconds(120)

        model.pointerEntered()
        model.openFromClick()
        model.escape()
        #expect(model.state == .closing)
        model.pointerExited()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(model.state == .closing)
        #expect(await eventually { model.state == .idle })
    }

    @Test
    func clickOpensImmediatelyAndPlaysOneHaptic() async {
        let haptics = HapticSpy()
        let settings = makeSettings(hoverDelay: 500, closeDelay: 40)
        let model = NotchViewModel(haptics: haptics, settings: settings)

        model.pointerEntered()
        #expect(haptics.count == 1)
        model.openFromClick()
        #expect(model.state == .expanded)
        #expect(haptics.count == 1, "the click arrives inside the 300 ms haptic rate limit")

        model.pointerExited()
        #expect(await eventually { model.state == .closing })
    }

    @Test
    func hoverDoesNotOpenWhenHoverOpeningIsDisabled() async {
        let settings = makeSettings(hoverDelay: 20, closeDelay: 20)
        settings.openOnHover = false
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)

        model.pointerEntered()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(model.state == .hoverArmed)

        model.openFromClick()
        #expect(model.state == .expanded)
    }

    @Test
    func swipeDownStretchesThenOpensPastSensitivity() {
        let haptics = HapticSpy()
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        settings.gestureSensitivity = 200
        let model = NotchViewModel(haptics: haptics, settings: settings)

        model.updateOpenGesture(translation: 50)
        #expect(model.state == .idle)
        #expect(model.gestureProgress == 5)

        model.updateOpenGesture(translation: 201)
        #expect(model.state == .expanded)
        #expect(model.gestureProgress == 0)
        #expect(haptics.count == 1)

        model.endGesture()
        #expect(model.gestureProgress == 0)
    }

    @Test
    func gestureProgressResetsWhenTheStateChanges() {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)

        model.updateOpenGesture(translation: 60)
        #expect(model.gestureProgress == 6)
        model.openPinned()
        #expect(model.gestureProgress == 0)
    }

    @Test
    func swipeUpClosesTheOpenShelfAndCanBeDisabled() {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        settings.gestureSensitivity = 100
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)

        model.openFromClick()
        #expect(model.state == .expanded)
        model.updateCloseGesture(translation: 40)
        #expect(model.gestureProgress == -8)
        model.updateCloseGesture(translation: 101)
        #expect(model.state == .closing)

        settings.closeGestureEnabled = false
        let locked = NotchViewModel(haptics: HapticSpy(), settings: settings)
        locked.openFromClick()
        locked.updateCloseGesture(translation: 500)
        #expect(locked.state == .expanded)
    }

    @Test
    func capturedClipPeeksThenFoldsAway() async {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        let model = NotchViewModel(items: Clip.debugPreviewItems, haptics: HapticSpy(), settings: settings)
        model.peekDuration = .milliseconds(40)
        model.closeAnimationDuration = .milliseconds(30)
        let clip = Clip.debugPreviewItems[1]

        model.presentCapturePeek(for: clip)
        #expect(model.state == .peeking)
        #expect(model.peekedClip?.id == clip.id)

        model.pointerExited()
        #expect(model.state == .peeking, "a peek is not cut short by pointer movement")

        #expect(await eventually { model.state == .closing })
        #expect(model.peekedClip == nil)
        #expect(await eventually { model.state == .idle })
    }

    @Test
    func hoveringThePeekArmsAHoverOpenWithAFreshTarget() async {
        let haptics = HapticSpy()
        let targets = TargetSpy()
        let settings = makeSettings(hoverDelay: 30, closeDelay: 500)
        let model = NotchViewModel(
            items: Clip.debugPreviewItems,
            targetProvider: targets,
            haptics: haptics,
            settings: settings
        )
        model.peekDuration = .milliseconds(40)

        model.presentCapturePeek(for: Clip.debugPreviewItems[0])
        model.pointerEntered()
        #expect(model.state == .peeking)
        #expect(targets.rememberCount == 1)
        #expect(await eventually { model.state == .hoverArmed })
        #expect(targets.rememberCount == 2)
        #expect(await eventually { model.state == .expanded })
    }

    @Test
    func peekIsSkippedWhileHoveringOrWhenDisabled() {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        let model = NotchViewModel(items: Clip.debugPreviewItems, haptics: HapticSpy(), settings: settings)

        model.pointerEntered()
        model.presentCapturePeek(for: Clip.debugPreviewItems[0])
        #expect(model.state == .hoverArmed)

        model.pointerExited()
        settings.showCapturePeek = false
        model.presentCapturePeek(for: Clip.debugPreviewItems[0])
        #expect(model.state == .hoverArmed, "the grace period is still running")
    }

    @Test
    func fullscreenRetractsAndRestoresTheIsland() {
        let model = NotchViewModel(haptics: HapticSpy(), settings: makeSettings(hoverDelay: 500, closeDelay: 500))

        model.pointerEntered()
        model.setFullscreen(true)
        #expect(model.state == .retractedForFullscreen)
        #expect(!model.isHovering)
        model.setFullscreen(false)
        #expect(model.state == .idle)
    }

    @Test
    func redundantFullscreenExitDoesNotDisturbAPeek() async {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        let model = NotchViewModel(items: Clip.debugPreviewItems, haptics: HapticSpy(), settings: settings)
        model.peekDuration = .milliseconds(40)
        model.closeAnimationDuration = .milliseconds(20)

        model.presentCapturePeek(for: Clip.debugPreviewItems[0])
        model.setFullscreen(false)
        #expect(model.state == .peeking)
        #expect(await eventually { model.state == .idle }, "the peek timer survived the no-op call")
    }

    @Test
    func enablingTheNotchRespectsAnActiveFullscreen() {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        settings.notchEnabled = false
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)
        model.fullscreenProvider = { true }
        #expect(model.state == .disabled)

        model.setNotchEnabled(true)
        #expect(model.state == .retractedForFullscreen)
    }

    @Test
    func closedHitAreaHugsTheDrawnNotch() {
        let geometry = Self.macBookGeometry
        let metrics = NotchGeometryResolver.metrics(state: .closing, geometry: geometry, preferredExpandedWidth: 640)

        #expect(metrics.interactiveSize == metrics.activationSize)
        #expect(metrics.interactiveSize.width == metrics.renderedSize.width + NotchSilhouette.activationHorizontalSlack)
        #expect(metrics.interactiveSize.height == metrics.renderedSize.height + NotchSilhouette.activationVerticalSlack)
    }

    @Test
    func idleNotchMatchesAtollAndDoesNotSwell() {
        let geometry = Self.macBookGeometry
        // Atoll: (hardware + 4) - 20 content box plus 14 pt on each side.
        let idle = NotchGeometryResolver.metrics(state: .idle, geometry: geometry, preferredExpandedWidth: 640)
        #expect(idle.renderedSize == CGSize(width: 197, height: 32))
        #expect(idle.activationSize == CGSize(width: 221, height: 38))

        let armed = NotchGeometryResolver.metrics(state: .hoverArmed, geometry: geometry, preferredExpandedWidth: 640)
        #expect(armed.renderedSize == idle.renderedSize, "only wings swell; the bare notch keeps its size")
    }

    @Test
    func activityWingsFollowAtollsArithmetic() {
        let center = IslandActivityCenter()
        let activity = FakeActivity(id: "music", priority: ClosedActivityPriority.music)
        center.register(activity)
        let rest = ClosedActivityContext(closedHeight: 32, notchWidth: 189, isHovering: false, gestureProgress: 0, hasHardwareNotch: true)
        let layout = center.layout(in: rest)
        #expect(layout == ClosedActivityLayout(leftWidth: 20, centerWidth: 189, rightWidth: 20, contentHeight: 20, outerHeight: 32))

        let hovered = center.layout(in: ClosedActivityContext(closedHeight: 32, notchWidth: 189, isHovering: true, gestureProgress: 12, hasHardwareNotch: true))
        #expect(hovered == ClosedActivityLayout(leftWidth: 38, centerWidth: 197, rightWidth: 38, contentHeight: 32, outerHeight: 40))

        let metrics = NotchGeometryResolver.metrics(state: .idle, geometry: Self.macBookGeometry, preferredExpandedWidth: 640, activity: layout)
        #expect(metrics.renderedSize == CGSize(width: 257, height: 32))
    }

    @Test
    func higherPriorityActivityWinsAndHiddenOnesAreSkipped() {
        let center = IslandActivityCenter()
        let music = FakeActivity(id: "music", priority: ClosedActivityPriority.music)
        let timer = FakeActivity(id: "timer", priority: ClosedActivityPriority.timer)
        let battery = FakeActivity(id: "battery", priority: ClosedActivityPriority.batteryHUD)
        battery.visible = false
        center.register(timer)
        center.register(music)
        center.register(battery)
        #expect(center.activeActivityID == "music")

        battery.visible = true
        center.reevaluate()
        #expect(center.activeActivityID == "battery")

        center.unregister(id: "battery")
        music.visible = false
        center.reevaluate()
        #expect(center.activeActivityID == "timer")
    }

    @Test
    func sneakPeekRequestsFromFeaturesDropUnderTheNotch() async {
        let center = IslandActivityCenter()
        let settings = makeSettings(hoverDelay: 500, closeDelay: 500)
        let model = NotchViewModel(haptics: HapticSpy(), activityCenter: center, settings: settings)
        model.closeAnimationDuration = .milliseconds(20)

        center.requestSneakPeek(SneakPeek(kind: .music, systemImage: "music.note", title: "Song", subtitle: "Artist", duration: .milliseconds(40)))
        #expect(model.state == .peeking)
        #expect(model.currentSneakPeek?.title == "Song")
        #expect(await eventually { model.state == .idle })
        #expect(model.currentSneakPeek == nil)
    }

    @Test
    func islandOpensOnHomeAndReturnsThereAfterClosing() async {
        let settings = makeSettings(hoverDelay: 500, closeDelay: 20)
        let model = NotchViewModel(haptics: HapticSpy(), settings: settings)
        model.closeAnimationDuration = .milliseconds(20)
        #expect(model.selectedTab == .home)
        #expect(model.availableTabs == [.home, .shelf, .timer, .stats, .notes, .clipboard])

        model.openFromClick()
        model.selectTab(.clipboard)
        #expect(model.tabSwitchForward)
        model.selectTab(.timer)
        #expect(!model.tabSwitchForward)
        model.escape()
        #expect(await eventually { model.state == .idle })
        #expect(model.selectedTab == .home)

        settings.showHomeTab = false
        model.normalizeSelectedTab()
        #expect(model.selectedTab == .shelf)
    }

    @Test
    func displaysWithoutANotchGetAMenuBarHeightIsland() {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            topInset: 24,
            hardwareNotchWidth: 0,
            isHardwareNotch: false
        )
        let idle = NotchGeometryResolver.metrics(state: .idle, geometry: geometry, preferredExpandedWidth: 640)
        #expect(idle.renderedSize == CGSize(width: 158, height: 24))

        let peek = NotchGeometryResolver.metrics(state: .peeking, geometry: geometry, preferredExpandedWidth: 640)
        #expect(peek.renderedSize == CGSize(width: NotchSilhouette.sneakPeekMinimumWidth, height: 24 + NotchSilhouette.sneakPeekRowHeight))
    }

    @Test
    func openSizesFollowTabsAndTabCount() {
        let geometry = Self.macBookGeometry
        let home = NotchGeometryResolver.metrics(state: .expanded, geometry: geometry, preferredExpandedWidth: 640, tab: .home, tabCount: 4)
        #expect(home.renderedSize == CGSize(width: 664, height: 212))
        let timer = NotchGeometryResolver.metrics(state: .expanded, geometry: geometry, preferredExpandedWidth: 640, tab: .timer, tabCount: 6)
        #expect(timer.renderedSize == CGSize(width: 794, height: 262))
    }

    private static let macBookGeometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
        topInset: 32,
        hardwareNotchWidth: 185,
        isHardwareNotch: true
    )

    @Test
    func topEdgeCountsAsInsideTheTrigger() {
        let rect = CGRect(x: 100, y: 900, width: 200, height: 56)
        #expect(NotchGeometryResolver.rectContainsIncludingTopEdge(rect, CGPoint(x: 200, y: 956)))
        #expect(NotchGeometryResolver.rectContainsIncludingTopEdge(rect, CGPoint(x: 300, y: 900)))
        #expect(!NotchGeometryResolver.rectContainsIncludingTopEdge(rect, CGPoint(x: 301, y: 920)))
        #expect(!rect.contains(CGPoint(x: 200, y: 956)))
    }

    /// Waits for `condition` with a ceiling, so tests do not depend on exact scheduling when
    /// many suites share the main actor.
    private func eventually(_ timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func makeSettings(hoverDelay: Int, closeDelay: Int) -> UserSettings {
        let suiteName = "NotchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        settings.hoverDelayMilliseconds = hoverDelay
        settings.closeDelayMilliseconds = closeDelay
        return settings
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

@MainActor
private final class HapticSpy: HapticFeedbackPerforming {
    private(set) var count = 0

    func perform() {
        count += 1
    }
}

@MainActor
private final class TargetSpy: PasteTargetProviding {
    private(set) var rememberCount = 0

    func rememberFrontmostApplication() {
        rememberCount += 1
    }

    func targetApplication() -> NSRunningApplication? { nil }
}

@MainActor
private final class FakeActivity: ClosedLiveActivity {
    let activityID: String
    let priority: Int
    var visible = true
    private let subject = PassthroughSubject<Void, Never>()

    init(id: String, priority: Int) {
        activityID = id
        self.priority = priority
    }

    var isActivityVisible: Bool { visible }
    var activityDidChange: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    func leftWing(in context: ClosedActivityContext) -> AnyView { AnyView(Color.clear) }
    func rightWing(in context: ClosedActivityContext) -> AnyView { AnyView(Color.clear) }
}
