import AppKit
import Combine
import OSLog
import QuartzCore
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI in a full-width transparent strip while claiming events only in the live island.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: CGRect = .zero
    var interactionEnabled = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionEnabled,
              NotchGeometryResolver.rectContainsIncludingTopEdge(interactiveRect, point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Primitive copy of a scroll-wheel event so it can cross into the main actor.
private struct ScrollSample: Sendable {
    let deltaX: CGFloat
    let deltaY: CGFloat
    let phaseRaw: UInt
    let momentumRaw: UInt
    let timestamp: TimeInterval

    init(_ event: NSEvent) {
        deltaX = event.scrollingDeltaX
        deltaY = event.scrollingDeltaY
        phaseRaw = event.phase.rawValue
        momentumRaw = event.momentumPhase.rawValue
        timestamp = event.timestamp
    }

    var phase: NSEvent.Phase { NSEvent.Phase(rawValue: phaseRaw) }
    var momentum: NSEvent.Phase { NSEvent.Phase(rawValue: momentumRaw) }
    /// Trackpad swipes carry phases; a mouse wheel carries none.
    var isTrackpadTouch: Bool { !phase.isEmpty }
}

/// AppKit delivers event-monitor callbacks on the main thread; this keeps that assumption
/// explicit and degrades to a hop instead of a trap if it ever stops holding.
private func onMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}

/// One fixed top-strip window. SwiftUI animates the island internally; the NSWindow never morphs.
@MainActor
final class NotchPanelController: NSObject {
    private static let panelHeight: CGFloat = 640
    private static let scrollNoiseThreshold: CGFloat = 0.2
    /// A wheel tick or a swipe that never reports an end is forgotten after this pause.
    private static let scrollIdleReset: Duration = .milliseconds(300)
    private static let logger = Logger(
        subsystem: "com.local.NotchIsland",
        category: "Windowing"
    )

    private let panel: NotchPanel
    private let hostingView: PassthroughHostingView<NotchRootView>
    private let model: NotchViewModel
    private var screen: NSScreen
    private var clickAwayMonitor: Any?
    private var eventMonitors: [Any] = []
    private var hoverTimer: Timer?
    private var pointerWasInside = false
    /// Where hovering arms the island (the generous sensor band).
    private var globalInteractiveRect: CGRect = .zero
    /// Where a click or swipe is accepted (the drawn notch plus a little slack).
    private var globalActivationRect: CGRect = .zero
    private var scrollAccumulated: CGFloat = 0
    private var lastScrollTimestamp: TimeInterval = 0
    private var scrollIdleTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    var currentScreen: NSScreen { screen }

    init(model: NotchViewModel) {
        self.model = model
        screen = Self.preferredScreen()
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        hostingView = PassthroughHostingView(rootView: NotchRootView(model: model))
        super.init()

        configure(panel)
        panel.contentView = hostingView

        // `@Published` emits before the property changes, so the sinks must use the emitted
        // value instead of reading the model, which still holds the previous value then.
        model.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                Self.logger.debug("Notch state changed to \(state.rawValue, privacy: .public)")
                self.resetScrollGesture()
                self.updateInteractiveZone(state: state)
                self.updateClickAwayMonitor(state: state)
                self.releaseKeyboardIfNeeded(state: state)
            }
            .store(in: &cancellables)
        model.$isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in self?.updateInteractiveZone(hovering: hovering) }
            .store(in: &cancellables)
        model.settings.$openNotchWidth
            .removeDuplicates()
            .sink { [weak self] width in self?.updateInteractiveZone(expandedWidth: width) }
            .store(in: &cancellables)
        model.$selectedTab
            .removeDuplicates()
            .sink { [weak self] tab in self?.updateInteractiveZone(tab: tab) }
            .store(in: &cancellables)
        // Activity and Home-layout changes are read after they land, on the next run-loop turn.
        model.activityCenter.$revision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateInteractiveZone() }
            .store(in: &cancellables)
        HomeLayoutState.shared.$extraHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateInteractiveZone() }
            .store(in: &cancellables)
        model.openSizeDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateInteractiveZone() }
            .store(in: &cancellables)
        model.$gestureProgress
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateInteractiveZone() }
            .store(in: &cancellables)
        model.settings.$hideFromScreenCapture
            .removeDuplicates()
            .sink { [weak self] hidden in self?.panel.sharingType = hidden ? .none : .readOnly }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        startHoverMonitoring()
        startEventMonitoring()
        relayout()
    }

    func show() {
        panel.orderFrontRegardless()
        updateInteractiveZone()
    }

    func stop() {
        if let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
            self.clickAwayMonitor = nil
        }
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors.removeAll()
        scrollIdleTask?.cancel()
        hoverTimer?.invalidate()
        hoverTimer = nil
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
    }

    func openPinned() {
        model.openPinned()
        panel.orderFrontRegardless()
    }

    private func configure(_ panel: NSPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.isExcludedFromWindowsMenu = true
        // Three levels above the menu bar: above status items and other menu-bar utilities.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .none
        panel.sharingType = model.settings.hideFromScreenCapture ? .none : .readOnly
    }

    @objc
    private func screenParametersChanged() {
        screen = Self.preferredScreen()
        relayout()
    }

    private func relayout() {
        let height = min(Self.panelHeight, screen.frame.height)
        let frame = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
        panel.setFrame(frame, display: true)
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        model.updateNotchGeometry(NotchGeometryResolver.resolve(screen: screen))
        Self.logger.info(
            "Panel laid out x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height) notchWidth=\(self.model.notchGeometry.syntheticOrHardwareWidth) topInset=\(self.model.notchGeometry.topInset)"
        )
        updateInteractiveZone()
    }

    private func updateInteractiveZone(
        state: NotchState? = nil,
        hovering: Bool? = nil,
        expandedWidth: Double? = nil,
        tab: NotchTab? = nil
    ) {
        let state = state ?? model.state
        let hovering = hovering ?? model.isHovering
        let showsActivity = state.isCollapsed || state == .peeking
        let metrics = NotchGeometryResolver.metrics(
            state: state,
            geometry: model.notchGeometry,
            preferredExpandedWidth: expandedWidth ?? model.settings.openNotchWidth,
            tab: tab ?? model.selectedTab,
            tabCount: model.availableTabs.count,
            extraOpenHeight: model.extraOpenHeight(for: tab ?? model.selectedTab),
            activity: showsActivity ? model.closedActivityLayout(hovering: hovering) : nil
        )
        hostingView.interactionEnabled = metrics.interactionEnabled
        hostingView.interactiveRect = NotchGeometryResolver.interactiveRect(
            containerSize: hostingView.bounds.size,
            interactiveSize: metrics.interactiveSize
        )
        globalInteractiveRect = topCenteredRect(size: metrics.interactiveSize)
        globalActivationRect = topCenteredRect(size: metrics.activationSize)
        refreshPointerState()
    }

    private func topCenteredRect(size: CGSize) -> CGRect {
        CGRect(
            x: panel.frame.midX - size.width / 2,
            y: panel.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// When the shelf folds away while the panel is key (the search field was used), hand
    /// keyboard focus back to the app the user was in instead of keeping it on an invisible
    /// island.
    private func releaseKeyboardIfNeeded(state: NotchState) {
        guard !state.showsShelfContent, panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func startHoverMonitoring() {
        let timer = Timer(
            timeInterval: 0.03,
            target: self,
            selector: #selector(pollPointerLocation),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    @objc
    private func pollPointerLocation() {
        refreshPointerState()
    }

    private func isPointerInsideInteractiveRegion() -> Bool {
        NotchGeometryResolver.rectContainsIncludingTopEdge(globalInteractiveRect, NSEvent.mouseLocation)
    }

    private func isPointerInsideActivationRegion() -> Bool {
        NotchGeometryResolver.rectContainsIncludingTopEdge(globalActivationRect, NSEvent.mouseLocation)
    }

    private func refreshPointerState() {
        guard hostingView.interactionEnabled else {
            if pointerWasInside {
                pointerWasInside = false
                model.pointerExited()
            }
            return
        }
        let isInside = isPointerInsideInteractiveRegion()
        guard isInside != pointerWasInside else { return }
        pointerWasInside = isInside
        if isInside {
            Self.logger.debug("Pointer entered interactive notch region")
            model.pointerEntered()
        } else {
            Self.logger.debug("Pointer exited interactive notch region")
            model.pointerExited()
        }
    }

    /// Mouse-down and scroll-wheel monitors.
    ///
    /// Clicks are watched globally as well as locally because a click on the very top
    /// pixel row can be routed by the system before SwiftUI's tap gesture sees it.
    /// Scroll events feed the swipe-to-open and swipe-to-close gestures. Neither monitor
    /// consumes events; the app underneath still receives them.
    private func startEventMonitoring() {
        let localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            onMainActor { self?.handleMouseDown() }
            return event
        })
        let globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            onMainActor { self?.handleMouseDown() }
        })
        let localScroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            let sample = ScrollSample(event)
            onMainActor { self?.handleScroll(sample) }
            return event
        })
        let globalScroll = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            let sample = ScrollSample(event)
            onMainActor { self?.handleScroll(sample) }
        })
        eventMonitors = [localClick, globalClick, localScroll, globalScroll].compactMap { $0 }
    }

    private func handleMouseDown() {
        guard hostingView.interactionEnabled,
              model.state.isCollapsed || model.state == .peeking,
              isPointerInsideActivationRegion() else { return }
        model.openFromClick()
    }

    private func handleScroll(_ sample: ScrollSample) {
        guard sample.timestamp != lastScrollTimestamp else { return }
        lastScrollTimestamp = sample.timestamp

        if sample.phase == .ended || sample.phase == .cancelled || sample.momentum == .ended {
            resetScrollGesture()
            return
        }
        guard model.settings.gesturesEnabled, hostingView.interactionEnabled else { return }
        // Momentum is the tail of a flick already released; a discrete gesture reads the touch.
        guard sample.momentum.isEmpty else { return }
        guard abs(sample.deltaY) > Self.scrollNoiseThreshold else { return }

        let opening = model.acceptsOpenGesture && isPointerInsideActivationRegion()
        let closing = model.acceptsCloseGesture && isPointerInsideInteractiveRegion()
        guard opening || closing else { return }
        // Sideways motion over the open shelf is the user scrolling its card rows.
        if closing, !sample.isTrackpadTouch || abs(sample.deltaX) > abs(sample.deltaY) {
            resetScrollGesture()
            return
        }
        // A downward two-finger swipe reports positive deltas; an upward swipe negative ones.
        let signed = opening ? sample.deltaY : -sample.deltaY
        scrollAccumulated = signed > 0 ? scrollAccumulated + signed : 0
        if opening {
            model.updateOpenGesture(translation: scrollAccumulated)
        } else {
            model.updateCloseGesture(translation: scrollAccumulated)
        }
        scheduleScrollIdleReset()
    }

    private func scheduleScrollIdleReset() {
        scrollIdleTask?.cancel()
        let pause = Self.scrollIdleReset
        scrollIdleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            self?.resetScrollGesture()
        }
    }

    private func resetScrollGesture() {
        scrollIdleTask?.cancel()
        scrollIdleTask = nil
        scrollAccumulated = 0
        model.endGesture()
    }

    private func updateClickAwayMonitor(state: NotchState) {
        if state == .pinnedOpen, clickAwayMonitor == nil {
            clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak model] _ in
                Task { @MainActor in model?.escape() }
            }
        } else if state != .pinnedOpen, let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
            self.clickAwayMonitor = nil
        }
    }

    /// The island belongs on the display with the hardware notch; the pointer only decides
    /// when no display has one.
    private static func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        if let main = NSScreen.main { return main }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.screens[0]
    }
}
