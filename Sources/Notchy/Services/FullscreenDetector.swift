import AppKit
import ApplicationServices

/// Reports whether an application is in native fullscreen on the island's screen.
///
/// Only public APIs are used. Candidate applications are the owners of on-screen windows
/// that fill the target screen below its safe area. When Accessibility is granted, each
/// candidate's windows are asked for the `AXFullScreen` attribute, which tells native
/// fullscreen apart from a merely zoomed window. Without Accessibility the system menu bar
/// decides: native fullscreen hides it, a zoomed window leaves it in place.
@MainActor
final class FullscreenDetector {
    var onChange: ((Bool) -> Void)?
    /// Whether hiding is wanted at all. When false the detector stays quiet and reports false.
    var isEnabled: () -> Bool = { true }
    private(set) var isFullscreen = false

    private let screenProvider: () -> NSScreen?
    private let settleDelay: Duration
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var evaluationTask: Task<Void, Never>?

    init(screenProvider: @escaping () -> NSScreen?, settleDelay: Duration = .milliseconds(500)) {
        self.screenProvider = screenProvider
        self.settleDelay = settleDelay
    }

    func start() {
        guard workspaceObservers.isEmpty, applicationObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification
        ]
        for name in workspaceNames {
            workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleEvaluation() }
            })
        }
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleEvaluation() }
        })
        scheduleEvaluation()
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
        for observer in applicationObservers { NotificationCenter.default.removeObserver(observer) }
        workspaceObservers.removeAll()
        applicationObservers.removeAll()
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    /// Space switches animate for a few hundred milliseconds; wait for them to settle
    /// before reading window geometry.
    func scheduleEvaluation() {
        evaluationTask?.cancel()
        let delay = settleDelay
        evaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    func evaluate() {
        let active = isEnabled() ? Self.detectFullscreen(on: screenProvider()) : false
        guard active != isFullscreen else { return }
        isFullscreen = active
        onChange?(active)
    }

    static func detectFullscreen(on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        let windows = onScreenWindows()
        var excluded: Set<pid_t> = [ProcessInfo.processInfo.processIdentifier]
        for finder in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder") {
            excluded.insert(finder.processIdentifier)
        }
        let candidates = screenFillingWindowOwners(on: screen, windows: windows).subtracting(excluded)
        guard !candidates.isEmpty else { return false }

        if AXIsProcessTrusted() {
            var answered = false
            for pid in candidates {
                guard let answer = applicationHasFullscreenWindow(pid: pid) else { continue }
                answered = true
                if answer { return true }
            }
            if answered { return false }
        }
        return !menuBarIsVisible(on: screen, windows: windows)
    }

    // MARK: Accessibility

    private static func applicationHasFullscreenWindow(pid: pid_t) -> Bool? {
        let application = AXUIElementCreateApplication(pid)
        // An unresponsive app must not stall the island's main thread.
        AXUIElementSetMessagingTimeout(application, 0.25)

        var answered = false
        if let focused: AXUIElement = copyElement(kAXFocusedWindowAttribute, of: application) {
            if let flag = fullscreenFlag(of: focused) {
                answered = true
                if flag { return true }
            }
        }
        if let windows: [AXUIElement] = copyElements(kAXWindowsAttribute, of: application) {
            for window in windows {
                if let flag = fullscreenFlag(of: window) {
                    answered = true
                    if flag { return true }
                }
            }
        }
        return answered ? false : nil
    }

    private static func fullscreenFlag(of window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func copyElement(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyElements(_ attribute: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID()
        else { return nil }
        let array = value as! CFArray
        var elements: [AXUIElement] = []
        for index in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            let item = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
            if CFGetTypeID(item) == AXUIElementGetTypeID() {
                elements.append(item as! AXUIElement)
            }
        }
        return elements
    }

    // MARK: Window list

    private static func onScreenWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    /// Window-server bounds use a top-left origin on the primary display.
    private static func screenTopInWindowServerCoordinates(_ screen: NSScreen) -> CGFloat {
        guard let primary = NSScreen.screens.first else { return 0 }
        return primary.frame.maxY - screen.frame.maxY
    }

    private static func bounds(of window: [String: Any]) -> CGRect? {
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    /// Owners of normal-level windows that cover `screen` below its safe area.
    private static func screenFillingWindowOwners(on screen: NSScreen, windows: [[String: Any]]) -> Set<pid_t> {
        let top = screenTopInWindowServerCoordinates(screen)
        let coveredHeight = screen.frame.height - screen.safeAreaInsets.top
        var owners: Set<pid_t> = []
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let bounds = bounds(of: window)
            else { continue }
            let fillsWidth = abs(bounds.width - screen.frame.width) <= 2
            let fillsHeight = bounds.height >= coveredHeight - 2
            let atLeft = abs(bounds.minX - screen.frame.minX) <= 2
            let atTop = bounds.minY <= top + screen.safeAreaInsets.top + 1
            if fillsWidth && fillsHeight && atLeft && atTop { owners.insert(pid) }
        }
        return owners
    }

    /// The menu bar is a window-server window at the main-menu level along the screen's top
    /// edge. Its name is withheld without Screen Recording access, so match on owner, level
    /// and position instead.
    private static func menuBarIsVisible(on screen: NSScreen, windows: [[String: Any]]) -> Bool {
        let top = screenTopInWindowServerCoordinates(screen)
        return windows.contains { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (window[kCGWindowLayer as String] as? Int) == Int(NSWindow.Level.mainMenu.rawValue),
                  let bounds = bounds(of: window)
            else { return false }
            return bounds.height < 60
                && abs(bounds.minY - top) <= 1
                && abs(bounds.minX - screen.frame.minX) <= 2
        }
    }
}
