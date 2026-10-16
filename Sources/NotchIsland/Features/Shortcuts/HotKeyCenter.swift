import AppKit
import Carbon.HIToolbox
import OSLog

/// Why a hot key could not be registered.
enum HotKeyError: Error, Equatable, Sendable {
    /// Another identifier in this app already owns the same keystroke.
    case duplicate(ownerID: String)
    /// Carbon refused because the keystroke is already registered (`eventHotKeyExistsErr`),
    /// usually by another app or by another part of NotchIsland.
    case alreadyTaken
    /// Any other Carbon failure.
    case rejected(status: Int32)

    var message: String {
        switch self {
        case .duplicate:
            "Another NotchIsland shortcut already uses this key combination."
        case .alreadyTaken:
            "Couldn’t activate: another app is already using this shortcut."
        case let .rejected(status):
            "Couldn’t activate this shortcut (error \(status))."
        }
    }
}

/// The registration primitive behind `HotKeyCenter`; tests substitute a fake.
@MainActor
protocol HotKeyBackend: AnyObject {
    /// Called with the numeric identifier of a hot key whenever it is pressed.
    var onPress: ((UInt32) -> Void)? { get set }
    /// Returns `noErr` on success.
    func register(keyCode: UInt32, carbonModifiers: UInt32, id: UInt32) -> OSStatus
    func unregister(id: UInt32)
}

/// Registers system-wide hot keys with the public Carbon Event Manager API
/// (`RegisterEventHotKey`), which needs neither Accessibility nor Input Monitoring access.
///
/// Carbon accepts a given handler procedure only once per event target, so one handler is
/// installed for the whole process and presses are routed to the backend that registered
/// them through process-unique hot-key IDs.
@MainActor
final class CarbonHotKeyBackend: HotKeyBackend {
    /// 'NIhk'. Events carrying another signature are passed on to other handlers.
    nonisolated static let signature: OSType = 0x4E49_686B

    var onPress: ((UInt32) -> Void)?

    private struct Route {
        weak var backend: CarbonHotKeyBackend?
        let localID: UInt32
    }

    private struct Registration {
        let carbonID: UInt32
        let ref: EventHotKeyRef
    }

    private static let logger = Logger(subsystem: "com.local.NotchIsland", category: "Shortcuts")
    private static var handlerRef: EventHandlerRef?
    private static var routes: [UInt32: Route] = [:]
    private static var nextCarbonID: UInt32 = 1

    private var registrations: [UInt32: Registration] = [:]

    init() {}

    func register(keyCode: UInt32, carbonModifiers: UInt32, id: UInt32) -> OSStatus {
        let handlerStatus = Self.installHandlerIfNeeded()
        guard handlerStatus == noErr else { return handlerStatus }
        unregister(id: id)

        let carbonID = Self.nextCarbonID
        Self.nextCarbonID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: carbonID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Self.logger.error("RegisterEventHotKey failed for key \(keyCode) modifiers \(carbonModifiers): \(status)")
            Self.removeHandlerIfUnused()
            return status == noErr ? OSStatus(eventInternalErr) : status
        }
        registrations[id] = Registration(carbonID: carbonID, ref: ref)
        Self.routes[carbonID] = Route(backend: self, localID: id)
        return noErr
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
        Self.routes[registration.carbonID] = nil
        Self.removeHandlerIfUnused()
    }

    private static func installHandlerIfNeeded() -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                // Leave other hot keys in the process (and other signatures) to their handlers.
                guard status == noErr, hotKeyID.signature == CarbonHotKeyBackend.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                CarbonHotKeyBackend.receive(carbonID: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            &ref
        )
        if status == noErr {
            handlerRef = ref
        } else {
            logger.error("InstallEventHandler failed: \(status)")
        }
        return status
    }

    private static func removeHandlerIfUnused() {
        guard routes.isEmpty, let handlerRef else { return }
        RemoveEventHandler(handlerRef)
        self.handlerRef = nil
    }

    /// Carbon dispatches application-target events on the main thread; this keeps that
    /// assumption explicit and degrades to a hop instead of a trap if it ever stops holding.
    nonisolated private static func receive(carbonID: UInt32) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { deliver(carbonID: carbonID) }
        } else {
            Task { @MainActor in deliver(carbonID: carbonID) }
        }
    }

    private static func deliver(carbonID: UInt32) {
        guard let route = routes[carbonID], let backend = route.backend else { return }
        backend.onPress?(route.localID)
    }
}

/// Owns NotchIsland's global hot keys: registration by string identifier, rebinding,
/// in-app conflict detection, and pausing while a shortcut recorder listens for keys.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter(backend: CarbonHotKeyBackend())

    private struct Entry {
        let numericID: UInt32
        var shortcut: Shortcut
        var handler: @MainActor () -> Void
        /// False while paused: the entry is remembered but not registered with Carbon.
        var isLive: Bool
    }

    private let backend: HotKeyBackend
    private var entries: [String: Entry] = [:]
    private var numericIDs: [String: UInt32] = [:]
    private var identifiers: [UInt32: String] = [:]
    private var nextNumericID: UInt32 = 1
    private var pauseDepth = 0

    init(backend: HotKeyBackend) {
        self.backend = backend
        backend.onPress = { [weak self] numericID in
            self?.handlePress(numericID: numericID)
        }
    }

    var isPaused: Bool { pauseDepth > 0 }

    var registeredIDs: Set<String> { Set(entries.keys) }

    func shortcut(for id: String) -> Shortcut? { entries[id]?.shortcut }

    /// Whether `id` is currently registered with the system (not merely remembered).
    func isLive(_ id: String) -> Bool { entries[id]?.isLive ?? false }

    /// The identifier that owns `shortcut`, if any.
    func owner(of shortcut: Shortcut) -> String? {
        entries.first { $0.value.shortcut == shortcut }?.key
    }

    /// Registers `shortcut` under `id`, replacing whatever `id` held before. Fails without
    /// touching the old binding when another identifier owns the keystroke.
    @discardableResult
    func register(
        id: String,
        shortcut: Shortcut,
        handler: @escaping @MainActor () -> Void
    ) -> Result<Void, HotKeyError> {
        if let owner = owner(of: shortcut), owner != id {
            return .failure(.duplicate(ownerID: owner))
        }
        if var existing = entries[id], existing.shortcut == shortcut, existing.isLive || isPaused {
            existing.handler = handler
            entries[id] = existing
            return .success(())
        }
        unregister(id: id)

        let numericID = numericID(for: id)
        guard !isPaused else {
            entries[id] = Entry(numericID: numericID, shortcut: shortcut, handler: handler, isLive: false)
            return .success(())
        }
        let status = backend.register(
            keyCode: shortcut.keyCode,
            carbonModifiers: shortcut.carbonModifiers,
            id: numericID
        )
        guard status == noErr else { return .failure(Self.error(for: status)) }
        entries[id] = Entry(numericID: numericID, shortcut: shortcut, handler: handler, isLive: true)
        return .success(())
    }

    /// Moves an existing registration to a new keystroke, keeping its handler.
    @discardableResult
    func rebind(id: String, to shortcut: Shortcut) -> Result<Void, HotKeyError> {
        guard let entry = entries[id] else { return .failure(.rejected(status: Int32(paramErr))) }
        return register(id: id, shortcut: shortcut, handler: entry.handler)
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if entry.isLive { backend.unregister(id: entry.numericID) }
    }

    func unregisterAll() {
        for id in Array(entries.keys) {
            unregister(id: id)
        }
    }

    /// Releases every hot key with the system so key presses reach a recorder instead of
    /// firing actions. Calls nest; each must be balanced by `resume()`.
    func pause() {
        pauseDepth += 1
        guard pauseDepth == 1 else { return }
        for (id, entry) in entries where entry.isLive {
            backend.unregister(id: entry.numericID)
            entries[id]?.isLive = false
        }
    }

    /// Re-registers everything paused. Returns the identifiers that could not be restored;
    /// those are dropped so callers can report them.
    @discardableResult
    func resume() -> [String: HotKeyError] {
        guard pauseDepth > 0 else { return [:] }
        pauseDepth -= 1
        guard pauseDepth == 0 else { return [:] }
        var failures: [String: HotKeyError] = [:]
        for (id, entry) in entries where !entry.isLive {
            let status = backend.register(
                keyCode: entry.shortcut.keyCode,
                carbonModifiers: entry.shortcut.carbonModifiers,
                id: entry.numericID
            )
            if status == noErr {
                entries[id]?.isLive = true
            } else {
                entries[id] = nil
                failures[id] = Self.error(for: status)
            }
        }
        return failures
    }

    /// Runs the handler for a pressed hot key. Internal so tests can simulate presses.
    func handlePress(numericID: UInt32) {
        guard !isPaused,
              let id = identifiers[numericID],
              let entry = entries[id],
              entry.isLive
        else { return }
        entry.handler()
    }

    private func numericID(for id: String) -> UInt32 {
        if let existing = numericIDs[id] { return existing }
        let value = nextNumericID
        nextNumericID &+= 1
        numericIDs[id] = value
        identifiers[value] = id
        return value
    }

    private static func error(for status: OSStatus) -> HotKeyError {
        status == OSStatus(eventHotKeyExistsErr) ? .alreadyTaken : .rejected(status: status)
    }
}
