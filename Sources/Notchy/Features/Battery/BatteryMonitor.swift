import Combine
import Foundation
import IOKit.ps

/// Watches the internal battery through IOKit's power-source notifications and Low Power
/// Mode changes, and delivers the changes one by one, a second apart.
///
/// `state` is the delivered state: the header indicator and the alerts read it, so they move
/// together with the events that raised them.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    /// Queues battery events and hands them out one per second.
    nonisolated static let defaultEventSpacing: Duration = .seconds(1)

    @Published private(set) var state: BatterySnapshot = .unavailable
    /// False until the first reading has arrived.
    @Published private(set) var hasLoaded = false
    /// Every delivered event, after `state` has been updated.
    let deliveries = PassthroughSubject<BatteryDelivery, Never>()

    private(set) var isRunning = false

    private let eventSpacing: Duration
    private let reader: @Sendable () -> BatterySnapshot
    private var lastReading: BatterySnapshot?
    private var pending: [BatteryEvent] = []
    private var drainTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var needsAnotherRead = false
    private var runLoopSource: CFRunLoopSource?
    private var callbackBox: PowerSourceCallbackBox?
    private var lowPowerObserver: NSObjectProtocol?

    init(
        eventSpacing: Duration = BatteryMonitor.defaultEventSpacing,
        reader: @escaping @Sendable () -> BatterySnapshot = { BatterySnapshot.read() }
    ) {
        self.eventSpacing = eventSpacing
        self.reader = reader
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installPowerSourceNotification()
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        callbackBox = nil
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        lowPowerObserver = nil
        readTask?.cancel()
        readTask = nil
        needsAnotherRead = false
        drainTask?.cancel()
        drainTask = nil
        pending.removeAll()
        lastReading = nil
    }

    /// Reads the battery off the main actor and queues whatever changed.
    func refresh() {
        guard readTask == nil else {
            needsAnotherRead = true
            return
        }
        let reader = self.reader
        readTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) { reader() }.value
            guard !Task.isCancelled, let self else { return }
            self.readTask = nil
            self.ingest(snapshot)
            if self.needsAnotherRead {
                self.needsAnotherRead = false
                self.refresh()
            }
        }
    }

    /// Compares a reading with the previous one and queues the differences. The first
    /// reading becomes the state directly, without events, so launching never raises an alert.
    func ingest(_ reading: BatterySnapshot) {
        guard let previous = lastReading else {
            lastReading = reading
            state = reading
            hasLoaded = true
            return
        }
        lastReading = reading
        if state.timeToEmpty != reading.timeToEmpty {
            state.timeToEmpty = reading.timeToEmpty
        }
        let events = BatteryEventRules.events(from: previous, to: reading)
        guard !events.isEmpty else { return }
        pending.append(contentsOf: events)
        drainIfNeeded()
    }

    private func drainIfNeeded() {
        guard drainTask == nil, !pending.isEmpty else { return }
        let spacing = eventSpacing
        drainTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: spacing)
                guard !Task.isCancelled, let self else { return }
                guard !self.pending.isEmpty else { break }
                self.deliver(self.pending.removeFirst())
                if self.pending.isEmpty { break }
            }
            self?.drainTask = nil
        }
    }

    private func deliver(_ event: BatteryEvent) {
        let before = state
        let after = before.applying(event)
        state = after
        deliveries.send(BatteryDelivery(event: event, before: before, after: after))
    }

    private func installPowerSourceNotification() {
        let box = PowerSourceCallbackBox { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        let context = Unmanaged.passUnretained(box).toOpaque()
        // The C callback cannot capture; it finds the box through the context pointer. The
        // box lives as long as the source is installed (both are released in `stop()`).
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceCallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        callbackBox = box
        runLoopSource = source
    }
}

/// Carries the power-source callback into the C function pointer IOKit calls.
private final class PowerSourceCallbackBox: Sendable {
    let fire: @Sendable () -> Void

    init(fire: @escaping @Sendable () -> Void) {
        self.fire = fire
    }
}
