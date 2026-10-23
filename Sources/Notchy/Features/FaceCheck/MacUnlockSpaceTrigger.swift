import Foundation
import IOKit.hid

/// An opt-in spacebar trigger. The HID element filter excludes every other key before
/// delivery. The owner starts it only during a locked, authorized session.
@MainActor
final class MacUnlockSpaceTrigger {
    private var manager: IOHIDManager?
    private var pressed = false
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    static var hasAccess: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    @discardableResult static func requestAccess() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    func start() {
        guard manager == nil, Self.hasAccess else { return }
        let candidate = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(candidate, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(candidate, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
            kIOHIDElementUsageKey: kHIDUsage_KeyboardSpacebar
        ] as CFDictionary)
        guard IOHIDManagerOpen(candidate, 0) == kIOReturnSuccess else { return }
        manager = candidate
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(candidate, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardSpacebar) else { return }
            let down = IOHIDValueGetIntegerValue(value) != 0
            MainActor.assumeIsolated {
                let owner = Unmanaged<MacUnlockSpaceTrigger>.fromOpaque(context).takeUnretainedValue()
                let justPressed = down && !owner.pressed
                owner.pressed = down
                if justPressed { owner.action() }
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, 0)
        self.manager = nil
        pressed = false
    }

    isolated deinit { stop() }
}
