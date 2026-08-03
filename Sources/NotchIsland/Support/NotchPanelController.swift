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
        guard interactionEnabled, interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One fixed top-strip window. SwiftUI animates the island internally; the NSWindow never morphs.
@MainActor
final class NotchPanelController: NSObject {
    private static let panelHeight: CGFloat = 640
    private static let logger = Logger(
        subsystem: "com.local.NotchIsland",
        category: "Windowing"
    )

    private let panel: NotchPanel
    private let hostingView: PassthroughHostingView<NotchRootView>
    private let model: NotchViewModel
    private var screen: NSScreen
    private var clickAwayMonitor: Any?
    private var hoverTimer: Timer?
    private var pointerWasInside = false
    private var globalInteractiveRect: CGRect = .zero
    private var cancellables: Set<AnyCancellable> = []

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

        model.$state
            .removeDuplicates()
            .sink { [weak self] state in
                Self.logger.debug("Notch state changed to \(state.rawValue, privacy: .public)")
                self?.updateInteractiveZone()
                self?.updateClickAwayMonitor()
            }
            .store(in: &cancellables)
        model.settings.$expandedWidth
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateInteractiveZone() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        startHoverMonitoring()
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
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .none
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

    private func updateInteractiveZone() {
        let metrics = NotchGeometryResolver.metrics(
            state: model.state,
            geometry: model.notchGeometry,
            preferredExpandedWidth: model.settings.expandedWidth
        )
        hostingView.interactionEnabled = metrics.interactionEnabled
        hostingView.interactiveRect = NotchGeometryResolver.interactiveRect(
            containerSize: hostingView.bounds.size,
            interactiveSize: metrics.interactiveSize
        )
        globalInteractiveRect = CGRect(
            x: panel.frame.midX - metrics.interactiveSize.width / 2,
            y: panel.frame.maxY - metrics.interactiveSize.height,
            width: metrics.interactiveSize.width,
            height: metrics.interactiveSize.height
        )
        refreshPointerState()
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

    private func refreshPointerState() {
        guard hostingView.interactionEnabled else {
            if pointerWasInside {
                pointerWasInside = false
                model.pointerExited()
            }
            return
        }
        let isInside = globalInteractiveRect.contains(NSEvent.mouseLocation)
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

    private func updateClickAwayMonitor() {
        if model.state == .pinnedOpen, clickAwayMonitor == nil {
            clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak model] _ in
                Task { @MainActor in model?.escape() }
            }
        } else if model.state != .pinnedOpen, let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
            self.clickAwayMonitor = nil
        }
    }

    private static func preferredScreen() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
