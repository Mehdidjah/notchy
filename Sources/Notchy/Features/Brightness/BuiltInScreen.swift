import AppKit
import CoreGraphics

/// The Mac's built-in screen as AppKit sees it. The backlight registry keeps publishing the
/// built-in panel's level even while the panel is off (lid closed in clamshell mode), so
/// the brightness monitor only trusts that level while this screen is online.
@MainActor
enum BuiltInScreen {
    /// The screen that `CGDisplayIsBuiltin`; nil when it is not online, as in clamshell mode.
    static func current() -> NSScreen? {
        NSScreen.screens.first(where: isBuiltIn)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    /// The built-in screen's current EDR headroom
    /// (`maximumExtendedDynamicRangeColorComponentValue`, at least 1), which macOS raises
    /// while HDR content is on screen and which scales the backlight output the registry
    /// reports. Nil when no built-in screen is online: the panel is off and its registry
    /// level would only show a stale or dark value.
    static func currentHeadroom() -> Double? {
        current().map { max(1, Double($0.maximumExtendedDynamicRangeColorComponentValue)) }
    }

    /// Whether a brightness key most plausibly went to the built-in panel.
    static func isBrightnessKeyTarget() -> Bool {
        let screens = NSScreen.screens
        return isBrightnessKeyTarget(
            builtInFrame: screens.first(where: isBuiltIn)?.frame,
            screenCount: screens.count,
            pointer: NSEvent.mouseLocation
        )
    }

    /// With another screen around, the same keys may be adjusting that screen (an Apple
    /// display macOS dims with them, or a DDC tool such as MonitorControl), so the built-in
    /// panel's level is only the answer when it is the sole screen or the pointer is on it.
    /// `NSMouseInRect` unflipped counts the top edge in, where the pointer sits at the notch.
    nonisolated static func isBrightnessKeyTarget(builtInFrame: CGRect?, screenCount: Int, pointer: CGPoint) -> Bool {
        guard let builtInFrame else { return false }
        return screenCount <= 1 || NSMouseInRect(pointer, builtInFrame, false)
    }
}

/// What identifies the screen setup: which displays are online and where they sit.
///
/// AppKit posts `didChangeScreenParametersNotification` for more than that: NSScreen.h
/// says it is posted whenever `maximumExtendedDynamicRangeColorComponentValue` changes, and
/// on an XDR panel showing HDR content that is every brightness step. Comparing this tells
/// a real change (lid opened or closed, display added or removed, resolution changed) from
/// a headroom-only one. The built-in panel coming and going shows up as its display ID.
struct ScreenTopology: Equatable, Sendable {
    struct Screen: Equatable, Sendable {
        var displayID: CGDirectDisplayID
        var frame: CGRect
    }

    /// Sorted by display ID, so the order AppKit lists screens in does not matter.
    let screens: [Screen]

    init(screens: [Screen]) {
        self.screens = screens.sorted { $0.displayID < $1.displayID }
    }

    @MainActor
    static func current() -> ScreenTopology {
        ScreenTopology(screens: NSScreen.screens.compactMap { screen in
            BuiltInScreen.displayID(of: screen).map { Screen(displayID: $0, frame: screen.frame) }
        })
    }
}
