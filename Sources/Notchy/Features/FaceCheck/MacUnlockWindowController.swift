import AppKit
import Combine
import SwiftUI
import os

/// A dedicated, non-activating surface. It contains only the scan, never other notch content.
@MainActor
final class MacUnlockWindowController: MacUnlockPresenting {
    private var panel: MacUnlockPanel?
    private var space: MacUnlockWindowSpace?
    private var delegated = false
    private var activity: FaceCheckLiveActivity?
    private var collapseTask: Task<Void, Never>?
    private var cursorTimer: Timer?
    private var geometry: MacUnlockGeometry?
    private var displayObserver: NSObjectProtocol?
    private var showsHint = false

    func show(activity: FaceCheckLiveActivity) -> Bool {
        collapseTask?.cancel()
        collapseTask = nil
        guard let screen = preferredScreen() else { return false }
        let geometry = MacUnlockGeometry.resolve(screen)
        self.geometry = geometry
        self.activity = activity
        if panel == nil {
            let panel = MacUnlockPanel(contentRect: CGRect(origin: .zero, size: geometry.windowSize),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.ignoresMouseEvents = true
            self.panel = panel
            displayObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.updateDisplay() } }
        }
        guard let panel else { return false }
        showsHint = false
        panel.setContentSize(geometry.windowSize)
        panel.contentView = content(activity: activity, geometry: geometry)
        position(panel, on: screen)
        if space == nil { space = MacUnlockWindowSpace() }
        guard let space else { return false }
        panel.orderFrontRegardless()
        guard space.attach(window: panel.windowNumber) else { panel.orderOut(nil); return false }
        delegated = true
        if cursorTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMousePassthrough() }
            }
            cursorTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        return true
    }

    func didUnlock() {
        // Leaving the lock-screen space does not reset the SwiftUI animation clock.
        if delegated, let panel { space?.detach(window: panel.windowNumber) }
        delegated = false
        panel?.orderFrontRegardless()
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        collapseTask?.cancel()
        collapseTask = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
        if delegated, let panel { space?.detach(window: panel.windowNumber) }
        delegated = false
        panel?.orderOut(nil)
        panel?.contentView = nil
        activity = nil
        showsHint = false
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateDisplay() {
        guard let panel, panel.isVisible, let screen = preferredScreen(), let activity else { return }
        let next = MacUnlockGeometry.resolve(screen)
        if geometry != next {
            geometry = next
            panel.setContentSize(next.windowSize)
            panel.contentView = content(activity: activity, geometry: next)
        }
        position(panel, on: screen)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - panel.frame.width / 2,
                                     y: screen.frame.maxY - panel.frame.height))
    }

    private func content(activity: FaceCheckLiveActivity, geometry: MacUnlockGeometry) -> NSView {
        NSHostingView(rootView: MacUnlockOverlayView(activity: activity, geometry: geometry) { [weak self] visible in
            self?.showsHint = visible
            self?.updateMousePassthrough()
        })
    }

    private func updateMousePassthrough() {
        guard let panel, let activity, let geometry else { return }
        let expanded = activity.phase != .preparing && activity.phase != .hidden
        let size = geometry.size(expanded: expanded, hovering: expanded)
        let top = panel.frame.maxY - geometry.topGap
        let hitArea = CGRect(x: panel.frame.midX - size.width / 2, y: top - size.height,
                             width: size.width, height: size.height)
        let hintArea = CGRect(x: panel.frame.midX - 140, y: top - size.height - 46, width: 280, height: 46)
        let mouse = NSEvent.mouseLocation
        panel.ignoresMouseEvents = !hitArea.contains(mouse) && !(showsHint && hintArea.contains(mouse))
    }

    isolated deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        cursorTimer?.invalidate()
        if delegated, let panel { space?.detach(window: panel.windowNumber) }
    }
}

private final class MacUnlockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The owner's lock-screen exception is confined to this optional window-server adapter.
/// Space mutations are asynchronous void calls. Confirm attachment with a separate query;
/// reading a return register as an error code rejects successful operations on newer systems.
@MainActor
final class MacUnlockWindowSpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias Level = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias Show = @convention(c) (Int32, CFArray) -> Void
    private typealias Attach = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias Detach = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Void
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let logger = Logger(subsystem: "com.local.Notchy", category: "MacUnlockWindow")
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: UInt64
    private let show: Show
    private let add: Attach
    private let remove: Detach
    private let destroy: Destroy?
    private let copySpaces: CopySpaces

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL) else {
            Self.logger.error("Lock-screen window framework could not load")
            return nil
        }
        func load<T>(_ name: String, _: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard let connectionFunction = load("SLSMainConnectionID", Connection.self),
              let create = load("SLSSpaceCreate", Create.self),
              let level = load("SLSSpaceSetAbsoluteLevel", Level.self),
              let show = load("SLSShowSpaces", Show.self),
              let add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", Attach.self),
              let remove = load("SLSRemoveWindowsFromSpaces", Detach.self),
              let copySpaces = load("SLSCopySpacesForWindows", CopySpaces.self) else {
            Self.logger.error("Lock-screen window operations are unavailable")
            dlclose(handle)
            return nil
        }
        let connection = connectionFunction()
        guard connection != 0 else {
            Self.logger.error("Lock-screen window connection is unavailable")
            dlclose(handle)
            return nil
        }
        let space = create(connection, 1, nil)
        guard space != 0 else {
            Self.logger.error("Lock-screen window space could not be created")
            dlclose(handle)
            return nil
        }
        level(connection, space, 400)
        self.handle = handle
        self.connection = connection
        self.space = space
        self.show = show
        self.add = add
        self.remove = remove
        self.destroy = load("SLSSpaceDestroy", Destroy.self)
        self.copySpaces = copySpaces
    }

    func attach(window: Int) -> Bool {
        guard let window = UInt32(exactly: window), window != 0 else { return false }
        // Reassert visibility on every attempt: display sleep can hide an existing space.
        show(connection, [space] as CFArray)
        add(connection, space, [window] as CFArray, 7)
        let attached = contains(window: Int(window))
        if !attached { Self.logger.error("Lock-screen window attachment was not confirmed") }
        return attached
    }

    func contains(window: Int) -> Bool {
        guard let window = UInt32(exactly: window), window != 0,
              let result = copySpaces(connection, 0xF, [window] as CFArray)?.takeRetainedValue(),
              let spaces = result as? [NSNumber] else { return false }
        // Include OS-owned spaces (bit 3); a mask of 7 omits this elevated space.
        return spaces.contains { $0.uint64Value == space }
    }

    func detach(window: Int) {
        guard let window = UInt32(exactly: window), window != 0 else { return }
        remove(connection, [window] as CFArray, [space] as CFArray)
    }

    isolated deinit {
        destroy?(connection, space)
        dlclose(handle)
    }
}
