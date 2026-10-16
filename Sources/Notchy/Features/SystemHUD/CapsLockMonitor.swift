import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Watches the Caps Lock state.
///
/// Listens to `flagsChanged` events. A local monitor sees them while
/// the app is active and a global one sees them everywhere once Accessibility is granted; both
/// re-read the flag at once, so the indicator toggles with the key press. Without
/// Accessibility the global monitor stays silent, so the combined session's modifier flags
/// are also polled every 150 ms (`CGEventSource.flagsState` needs no permission).
@MainActor
final class CapsLockMonitor: ObservableObject {
    static let shared = CapsLockMonitor(observesKeyEvents: true)

    static let pollInterval: Duration = .milliseconds(150)
    /// The indicator toggles with this spring.
    static let toggleAnimation = Animation.spring(response: 0.32, dampingFraction: 0.85)

    @Published private(set) var isCapsLockOn = false
    @Published private(set) var isRunning = false

    private var pollTask: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let readState: @MainActor () -> Bool
    private let observesKeyEvents: Bool

    /// `observesKeyEvents` installs the `flagsChanged` monitors; tests that inject a reader
    /// leave it off so real key presses cannot interfere.
    init(
        readState: @escaping @MainActor () -> Bool = { CapsLockMonitor.systemCapsLockState() },
        observesKeyEvents: Bool = false
    ) {
        self.readState = readState
        self.observesKeyEvents = observesKeyEvents
    }

    static func systemCapsLockState() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isCapsLockOn = readState()
        installKeyMonitors()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        removeKeyMonitors()
        isRunning = false
        if isCapsLockOn { isCapsLockOn = false }
    }

    /// Reads the flag once; called by the poll loop, the key monitors and tests.
    func poll() {
        let state = readState()
        guard state != isCapsLockOn else { return }
        withAnimation(Self.toggleAnimation) { isCapsLockOn = state }
    }

    // MARK: Key monitors

    private func installKeyMonitors() {
        guard observesKeyEvents, localMonitor == nil, globalMonitor == nil else { return }
        // Both handlers are called on the main thread.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.poll() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func removeKeyMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}
