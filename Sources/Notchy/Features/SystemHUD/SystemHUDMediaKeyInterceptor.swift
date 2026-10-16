import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// A media key decoded from an `NX_SYSDEFINED` event's `data1`.
struct SystemHUDMediaKey: Equatable, Sendable {
    /// `NX_KEYTYPE_*` code.
    var keyCode: Int
    var isKeyDown: Bool
    var isRepeat: Bool

    static let soundUp = 0
    static let soundDown = 1
    static let brightnessUp = 2
    static let brightnessDown = 3
    static let mute = 7

    /// `NSEvent` subtype of auxiliary control buttons (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
    static let auxiliaryControlSubtype: Int16 = 8
    /// `NX_SYSDEFINED`.
    static let systemDefinedEventType: UInt32 = 14

    /// Key code in the high 16 bits; state 0xA (down) / 0xB (up) in bits 8-15; repeat in bit 0.
    init(data1: Int) {
        keyCode = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        isKeyDown = ((flags & 0xFF00) >> 8) == 0xA
        isRepeat = (flags & 0x1) == 1
    }

    init(keyCode: Int, isKeyDown: Bool, isRepeat: Bool) {
        self.keyCode = keyCode
        self.isKeyDown = isKeyDown
        self.isRepeat = isRepeat
    }

    var isVolumeKey: Bool {
        keyCode == Self.soundUp || keyCode == Self.soundDown || keyCode == Self.mute
    }

    var isBrightnessKey: Bool {
        keyCode == Self.brightnessUp || keyCode == Self.brightnessDown
    }

    /// A brightness key going down, repeats included: holding the key keeps stepping the
    /// level, and each step should keep the HUD up. Nil for releases and other keys.
    var brightnessPress: BrightnessKeyDirection? {
        guard isKeyDown else { return nil }
        switch keyCode {
        case Self.brightnessUp: return .up
        case Self.brightnessDown: return .down
        default: return nil
        }
    }
}

/// Which way a brightness key asks the level to go.
enum BrightnessKeyDirection: Sendable, Equatable {
    case up
    case down
}

/// What a swallowed volume key asks for.
enum SystemHUDMediaKeyCommand: Equatable, Sendable {
    case volumeUp(fine: Bool)
    case volumeDown(fine: Bool)
    case toggleMute

    /// Option+Shift gives the fine step.
    static func make(for key: SystemHUDMediaKey, modifiers: NSEvent.ModifierFlags) -> SystemHUDMediaKeyCommand? {
        guard key.isKeyDown else { return nil }
        let fine = modifiers.contains(.option) && modifiers.contains(.shift)
        switch key.keyCode {
        case SystemHUDMediaKey.soundUp: return .volumeUp(fine: fine)
        case SystemHUDMediaKey.soundDown: return .volumeDown(fine: fine)
        case SystemHUDMediaKey.mute: return key.isRepeat ? nil : .toggleMute
        default: return nil
        }
    }
}

/// How hard to keep trying to install the tap while Accessibility is not yet granted:
/// every 2 s for the first minute, then every 15 s, giving up after an hour.
enum SystemHUDTapRetryPolicy {
    static let fastInterval: Duration = .seconds(2)
    static let slowInterval: Duration = .seconds(15)
    static let fastAttemptLimit = 30
    static let giveUpAfter: Duration = .seconds(3600)

    static func interval(afterAttempt attempt: Int) -> Duration {
        attempt < fastAttemptLimit ? fastInterval : slowInterval
    }
}

/// Swallows the hardware volume keys with a public `CGEventTap` so the macOS bezel never
/// appears, and hands them to `onCommand`. Brightness keys always pass through unchanged
/// (there is no public API to set a built-in display's brightness, so macOS must still act
/// on them); their key-downs are reported to `onBrightnessKey` so the brightness HUD knows
/// a key, not auto-brightness or idle dimming, moved the level, and can show the level when
/// the key cannot move it (already at 0 % or 100 %).
///
/// The tap needs Accessibility. Until it is granted the keys reach macOS untouched (the HUD
/// still follows the level through CoreAudio and the backlight registry) and the tap is
/// retried on a schedule.
@MainActor
final class SystemHUDMediaKeyInterceptor: ObservableObject {
    static let shared = SystemHUDMediaKeyInterceptor()

    /// True while the tap is installed and swallowing volume keys.
    @Published private(set) var isIntercepting = false
    /// True while the tap is installed and reporting brightness keys.
    @Published private(set) var isObservingBrightnessKeys = false
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    var onCommand: ((SystemHUDMediaKeyCommand, NSEvent.ModifierFlags) -> Void)?
    /// A brightness key went down (repeats included). The event itself is never altered.
    var onBrightnessKey: ((BrightnessKeyDirection) -> Void)?

    /// Swallow volume keys.
    private var wantsInterception = false
    /// Report brightness keys.
    private var wantsBrightnessKeys = false
    private var wantsTap: Bool { wantsInterception || wantsBrightnessKeys }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTask: Task<Void, Never>?
    private var didPromptForAccessibility = false

    init() {}

    /// Turns volume-key interception on or off, keeping brightness-key reporting as it is.
    func setEnabled(_ enabled: Bool) {
        configure(interceptVolumeKeys: enabled, observeBrightnessKeys: wantsBrightnessKeys)
    }

    /// Installs the tap while either job needs it and removes it otherwise. Wanting it
    /// without Accessibility starts the retry poll.
    func configure(interceptVolumeKeys: Bool, observeBrightnessKeys: Bool) {
        wantsInterception = interceptVolumeKeys
        wantsBrightnessKeys = observeBrightnessKeys
        if wantsTap {
            refreshAccessibility()
            if !installTapIfPossible() { scheduleRetry() }
        } else {
            cancelRetry()
            removeTap()
        }
        publishTapState()
    }

    /// Shows the system Accessibility prompt once per launch.
    func requestAccessibility() {
        guard !AXIsProcessTrusted() else {
            refreshAccessibility()
            return
        }
        if !didPromptForAccessibility {
            didPromptForAccessibility = true
            // The value of `kAXTrustedCheckOptionPrompt`; the global itself is not
            // concurrency-safe to read under Swift 6.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        if wantsTap { scheduleRetry() }
    }

    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        if isAccessibilityTrusted != trusted { isAccessibilityTrusted = trusted }
    }

    // MARK: Tap

    /// Always an active (`.defaultTap`) tap, even when only brightness keys are wanted: a
    /// listen-only tap on key events can fall under Input Monitoring, a separate permission
    /// the app never asks for, while the active tap is covered by the Accessibility grant
    /// volume interception already uses. Brightness and other non-volume events are always
    /// returned unchanged.
    @discardableResult
    private func installTapIfPossible() -> Bool {
        guard wantsTap else { return false }
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1) << CGEventMask(SystemHUDMediaKey.systemDefinedEventType)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        var created: CFMachPort?
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            created = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: systemHUDMediaKeyTapCallback,
                userInfo: userInfo
            )
            if created != nil { break }
        }
        guard let created else { return false }

        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        // The callback relies on running on the main run loop (see `MainActor.assumeIsolated`).
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        publishTapState()
        cancelRetry()
        return true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        publishTapState()
    }

    private func publishTapState() {
        let intercepting = tap != nil && wantsInterception
        if isIntercepting != intercepting { isIntercepting = intercepting }
        let observing = tap != nil && wantsBrightnessKeys
        if isObservingBrightnessKeys != observing { isObservingBrightnessKeys = observing }
    }

    private func scheduleRetry() {
        guard retryTask == nil, tap == nil, wantsTap else { return }
        retryTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let started = clock.now
            var attempt = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: SystemHUDTapRetryPolicy.interval(afterAttempt: attempt))
                attempt += 1
                guard !Task.isCancelled, let self else { return }
                self.refreshAccessibility()
                if self.installTapIfPossible() || !self.wantsTap { break }
                if clock.now - started >= SystemHUDTapRetryPolicy.giveUpAfter { break }
            }
            self?.retryTask = nil
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// Only volume keys are ever swallowed, and only while interception is on. Brightness
    /// keys must reach macOS, the only thing that can set a built-in display's brightness.
    static func swallows(_ key: SystemHUDMediaKey, interceptingVolume: Bool) -> Bool {
        interceptingVolume && key.isVolumeKey
    }

    /// Returns true when the event should be swallowed. Runs on the main thread.
    fileprivate func handle(type: CGEventType, key: SystemHUDMediaKey?, modifiers: NSEvent.ModifierFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if wantsTap, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let key else { return false }
        if let direction = key.brightnessPress, wantsBrightnessKeys {
            // Keep the callback short: the registry read happens after it returns.
            Task { @MainActor [weak self] in self?.onBrightnessKey?(direction) }
        }
        guard Self.swallows(key, interceptingVolume: wantsInterception) else { return false }
        if let command = SystemHUDMediaKeyCommand.make(for: key, modifiers: modifiers) {
            // Keep the callback short: CoreAudio work happens after it returns.
            Task { @MainActor [weak self] in self?.onCommand?(command, modifiers) }
        }
        // Key-ups and repeats of handled keys are swallowed too, so macOS sees nothing.
        return true
    }
}

/// C callback for the tap. The run-loop source lives on the main run loop, so it always runs
/// on the main thread; the event is decoded into Sendable values before hopping onto the
/// main actor's isolation.
private func systemHUDMediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let address = UInt(bitPattern: userInfo)
    let decoded = decodeSystemHUDMediaKey(type: type, event: event)
    let swallow = MainActor.assumeIsolated { () -> Bool in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
        let interceptor = Unmanaged<SystemHUDMediaKeyInterceptor>.fromOpaque(pointer).takeUnretainedValue()
        return interceptor.handle(type: type, key: decoded?.key, modifiers: decoded?.modifiers ?? [])
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

private func decodeSystemHUDMediaKey(
    type: CGEventType,
    event: CGEvent
) -> (key: SystemHUDMediaKey, modifiers: NSEvent.ModifierFlags)? {
    guard type.rawValue == SystemHUDMediaKey.systemDefinedEventType,
          let nsEvent = NSEvent(cgEvent: event),
          nsEvent.subtype.rawValue == SystemHUDMediaKey.auxiliaryControlSubtype else {
        return nil
    }
    return (SystemHUDMediaKey(data1: nsEvent.data1), nsEvent.modifierFlags)
}
