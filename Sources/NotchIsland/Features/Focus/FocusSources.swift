import Foundation

/// A Focus on/off event from the system, with whatever metadata it carried.
struct FocusNotificationEvent: Equatable, Sendable {
    var isActive: Bool
    var metadata: FocusMetadata
}

/// Listens for the distributed notifications macOS posts when Focus turns on and off.
///
/// The names are undocumented but have been posted since macOS 12; they are received through
/// the public `DistributedNotificationCenter`. Delivery is immediate so the island updates even
/// while NotchIsland is in the background (the default would hold them until it is active).
final class FocusNotificationObserver: NSObject, @unchecked Sendable {
    static let enabledName = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let disabledName = Notification.Name("_NSDoNotDisturbDisabledNotification")

    private let handler: @Sendable (FocusNotificationEvent) -> Void

    init(handler: @escaping @Sendable (FocusNotificationEvent) -> Void) {
        self.handler = handler
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(focusEnabled(_:)), name: Self.enabledName,
            object: nil, suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self, selector: #selector(focusDisabled(_:)), name: Self.disabledName,
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    func invalidate() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func focusEnabled(_ notification: Notification) {
        deliver(notification, isActive: true)
    }

    @objc private func focusDisabled(_ notification: Notification) {
        deliver(notification, isActive: false)
    }

    private func deliver(_ notification: Notification, isActive: Bool) {
        let metadata = FocusPayloadSearch.metadata(userInfo: notification.userInfo, object: notification.object)
        handler(FocusNotificationEvent(isActive: isActive, metadata: metadata))
    }
}

/// Polls the Focus database every 2 s (first read after 1 s, 250 ms leeway), Atoll's cadence.
///
/// Each tick re-checks Full Disk Access and reports changes; with access it re-reads
/// ModeConfigurations.json when it changes and, when `readsAssertions` is set, Assertions.json
/// when it changes. Assertions are not read for 4 s after a notification, so a file that has
/// not been flushed yet cannot undo the notification.
final class FocusDatabasePoller: @unchecked Sendable {
    struct Callbacks: Sendable {
        var access: @Sendable (Bool) -> Void
        var assertions: @Sendable (FocusAssertionsReading) -> Void
        var configurations: @Sendable ([FocusModeConfiguration]) -> Void
    }

    static let notificationCooldown: TimeInterval = 4

    private let queue = DispatchQueue(label: "NotchIsland.Focus.Database", qos: .utility)
    private let callbacks: Callbacks

    // Confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var readsAssertions = true
    private var lastAccess: Bool?
    private var lastAssertionsDate: Date?
    private var lastConfigurationsDate: Date?
    private var lastNotification: Date = .distantPast

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    func start(readsAssertions: Bool) {
        queue.async { [self] in
            self.readsAssertions = readsAssertions
            lastAssertionsDate = nil
            lastConfigurationsDate = nil
            lastAccess = nil
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2), leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func noteNotification() {
        queue.async { [self] in lastNotification = Date() }
    }

    /// Re-reads everything at once, for example after the user granted Full Disk Access.
    func refreshNow() {
        queue.async { [self] in
            lastAssertionsDate = nil
            lastConfigurationsDate = nil
            lastAccess = nil
            poll()
        }
    }

    private func poll() {
        let access = FocusDatabase.hasFullDiskAccess()
        if access != lastAccess {
            lastAccess = access
            callbacks.access(access)
        }
        guard access else { return }

        let configurationsDate = FocusDatabase.modificationDate(of: FocusDatabase.modeConfigurationsURL)
        if lastConfigurationsDate == nil || configurationsDate != lastConfigurationsDate {
            lastConfigurationsDate = configurationsDate ?? .distantPast
            let data = (try? Data(contentsOf: FocusDatabase.modeConfigurationsURL)) ?? Data()
            callbacks.configurations(FocusDatabase.parseModeConfigurations(data))
        }

        guard readsAssertions,
              Date().timeIntervalSince(lastNotification) >= Self.notificationCooldown
        else { return }
        let assertionsDate = FocusDatabase.modificationDate(of: FocusDatabase.assertionsURL)
        if let assertionsDate, let lastAssertionsDate, assertionsDate <= lastAssertionsDate { return }
        lastAssertionsDate = assertionsDate
        // An unreadable or unexpected file counts as "no Focus", as in Atoll.
        let reading = (try? Data(contentsOf: FocusDatabase.assertionsURL))
            .flatMap(FocusDatabase.parseAssertions) ?? .inactive
        callbacks.assertions(reading)
    }
}

/// Optional "DevTools" source: tails the unified log for duetexpertd's Focus messages to learn
/// the active mode's identifier and name without Full Disk Access, and seeds the state from
/// recent history at start. Runs `/usr/bin/log` as a child process; nothing else is touched.
final class FocusLogStream: @unchecked Sendable {
    private static let predicate = #"process == "duetexpertd" AND eventMessage CONTAINS "semanticModeIdentifier""#

    private let queue = DispatchQueue(label: "NotchIsland.Focus.LogStream", qos: .utility)
    private let onEvent: @Sendable (FocusPayloadSearch.LogEvent) -> Void
    /// Called once with the mode found in recent history when Focus was already on.
    private let onInitialMode: @Sendable (FocusMetadata) -> Void

    // Confined to `queue`.
    private var process: Process?
    private var buffer = Data()
    private var generation = 0

    init(
        onEvent: @escaping @Sendable (FocusPayloadSearch.LogEvent) -> Void,
        onInitialMode: @escaping @Sendable (FocusMetadata) -> Void
    ) {
        self.onEvent = onEvent
        self.onInitialMode = onInitialMode
    }

    func start() {
        queue.async { [self] in
            guard process == nil else { return }
            generation &+= 1
            let current = generation
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream", "--no-backtrace", "--style", "compact", "--level", "info", "--predicate", Self.predicate
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { [weak self] in
                    guard let self, self.generation == current else { return }
                    if data.isEmpty {
                        self.tearDown()
                    } else {
                        self.consume(data)
                    }
                }
            }
            process.terminationHandler = { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.tearDown()
                }
            }
            do {
                try process.run()
                self.process = process
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        seedFromHistory()
    }

    func stop() {
        queue.async { [self] in
            generation &+= 1
            tearDown()
        }
    }

    private func tearDown() {
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        buffer.removeAll(keepingCapacity: false)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8),
                  let event = FocusPayloadSearch.logEvent(fromLine: line)
            else { continue }
            onEvent(event)
        }
    }

    /// `log stream` only sees future events; look back through recent history, in growing
    /// windows, for the last Focus change.
    private func seedFromHistory() {
        let onInitialMode = onInitialMode
        DispatchQueue.global(qos: .utility).async {
            for window in ["5m", "1h", "24h"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                process.arguments = [
                    "show", "--last", window, "--debug", "--style", "compact", "--predicate", Self.predicate
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { return }
                // Drain before waiting so a large history cannot fill the pipe and stall `log`.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let lines = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { $0.contains("semanticModeIdentifier") && !$0.hasPrefix("Filtering") }
                guard let last = lines.last else { continue }
                // "starting: 0" records a Focus ending: nothing is on.
                guard !last.contains("starting: 0") else { return }
                let metadata = FocusMetadata(
                    identifier: FocusPayloadSearch.identifier(inText: last),
                    name: FocusPayloadSearch.name(inText: last)
                )
                if !metadata.isEmpty { onInitialMode(metadata) }
                return
            }
        }
    }
}
