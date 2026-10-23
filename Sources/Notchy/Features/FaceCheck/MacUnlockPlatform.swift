import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Security
import os

struct MacUnlockSession: Equatable, Sendable {
    var userID: UInt32
    var securitySessionID: UInt32
}

/// The public authorization-session identifier tracks the caller's login session.
/// The optional Core Graphics console-set key describes hardware and may be absent.
struct MacUnlockSecuritySession: Equatable, Sendable {
    let id: UInt32
    let attributes: SessionAttributeBits

    private init(id: UInt32, attributes: SessionAttributeBits) {
        self.id = id
        self.attributes = attributes
    }

    static func read(status: OSStatus, id: UInt32, attributes: SessionAttributeBits) -> Self? {
        guard status == errSecSuccess, id != noSecuritySession, id < UInt32.max - 1,
              attributes.contains(.sessionHasGraphicAccess),
              !attributes.contains(.sessionIsRemote), !attributes.contains(.sessionIsRoot) else { return nil }
        return Self(id: id, attributes: attributes)
    }

    static func current() -> Self? {
        var id = noSecuritySession
        var attributes: SessionAttributeBits = []
        let status = SessionGetInfo(callerSecuritySession, &id, &attributes)
        return read(status: status, id: id, attributes: attributes)
    }
}

enum MacUnlockScreenState: Equatable, Sendable {
    case locked(MacUnlockSession)
    case unlocked(MacUnlockSession)
    case unavailable
}

@MainActor
protocol MacUnlockPlatform: AnyObject {
    var screenState: MacUnlockScreenState { get }
    var accessibilityGranted: Bool { get }
    /// Delivery is an attempt. The caller must independently observe the same session unlock.
    func submit(password: Data, for session: MacUnlockSession, stillValid: @escaping @MainActor () -> Bool) async throws
}

enum MacUnlockPlatformError: LocalizedError, Equatable {
    case accessibilityRequired, sessionChanged, destinationUnavailable, destinationChanged
    case fieldCannotBeCleared, inputNotAccepted, invalidPassword, passwordTooLong
    case eventCreationFailed, cancelled, submissionInProgress

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Accessibility access is required to enter the saved password."
        case .sessionChanged: "The original locked user session could no longer be verified."
        case .destinationUnavailable: "The system's focused secure password field is not accessible. Enter your password manually."
        case .destinationChanged: "The secure password field or its system process changed. No further keys were sent."
        case .fieldCannotBeCleared: "The system password field could not be verified empty. Enter your password manually."
        case .inputNotAccepted: "The system password field did not accept the expected input. Enter your password manually."
        case .invalidPassword: "The saved password must be valid UTF-8 without control, line-break, or formatting characters."
        case .passwordTooLong: "The saved password exceeds the supported input length."
        case .eventCreationFailed: "macOS could not create a keyboard event."
        case .cancelled: "Password entry was cancelled."
        case .submissionInProgress: "A password entry attempt is already in progress."
        }
    }
}

/// Notifications are hints only. A missing lock key does not by itself establish an unlock.
enum MacUnlockSessionParser {
    static let lockKey = "CGSSessionScreenIsLocked"

    static func parse(
        _ dictionary: [String: Any]?, ownUserID: UInt32, protectedDataAvailable: Bool,
        securitySession: MacUnlockSecuritySession?
    ) -> MacUnlockScreenState {
        guard let dictionary, let securitySession,
              let uid = unsignedInteger(dictionary[kCGSessionUserIDKey as String]), uid == ownUserID,
              boolean(dictionary[kCGSessionOnConsoleKey as String]) == true,
              boolean(dictionary[kCGSessionLoginDoneKey as String]) == true else { return .unavailable }
        let session = MacUnlockSession(userID: uid, securitySessionID: securitySession.id)
        if let rawLock = dictionary[lockKey] {
            guard let locked = boolean(rawLock) else { return .unavailable }
            if locked { return .locked(session) }
        }
        return protectedDataAvailable ? .unlocked(session) : .unavailable
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func unsignedInteger(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        let cfNumber = unsafeBitCast(number, to: CFNumber.self)
        guard !CFNumberIsFloatType(cfNumber) else { return nil }
        var integer: Int64 = 0
        guard CFNumberGetValue(cfNumber, .sInt64Type, &integer) else { return nil }
        return UInt32(exactly: integer)
    }
}

/// Contains no event objects and performs no system interaction. Its sole text allocation is
/// explicitly erased on all exit paths; the caller remains responsible for its input Data.
final class MacUnlockPasswordPlan {
    enum Step: Equatable, Sendable {
        case clearFocusedField
        case unicode(Range<Int>)
        case submitReturn
    }

    static let maximumUTF8Bytes = 1_024
    static let maximumUTF16Units = 512
    static let batchSize = 16
    private var storage = Data(count: maximumUTF16Units * MemoryLayout<UInt16>.stride)
    private(set) var unitCount = 0
    private(set) var steps: [Step] = []

    init(password: Data) throws {
        do {
            guard !password.isEmpty else { throw MacUnlockPlatformError.invalidPassword }
            guard password.count <= Self.maximumUTF8Bytes else { throw MacUnlockPlatformError.passwordTooLong }
            try password.withUnsafeBytes { bytes in
                let input = bytes.bindMemory(to: UInt8.self)
                try storage.withUnsafeMutableBytes { output in
                    let units = output.bindMemory(to: UInt16.self)
                    var cursor = 0
                    while cursor < input.count {
                        let scalar = try Self.nextScalar(in: input, cursor: &cursor)
                        // These private-use characters encode native navigation/function keys.
                        guard !(0xf700...0xf8ff).contains(scalar) else { throw MacUnlockPlatformError.invalidPassword }
                        guard let unicode = Unicode.Scalar(scalar) else { throw MacUnlockPlatformError.invalidPassword }
                        switch unicode.properties.generalCategory {
                        case .control, .format, .lineSeparator, .paragraphSeparator:
                            throw MacUnlockPlatformError.invalidPassword
                        default: break
                        }
                        let needed = scalar > 0xffff ? 2 : 1
                        guard unitCount + needed <= units.count else { throw MacUnlockPlatformError.passwordTooLong }
                        if needed == 1 {
                            units[unitCount] = UInt16(scalar)
                        } else {
                            let offset = scalar - 0x10000
                            units[unitCount] = UInt16(0xd800 + (offset >> 10))
                            units[unitCount + 1] = UInt16(0xdc00 + (offset & 0x3ff))
                        }
                        unitCount += needed
                    }
                }
            }
            steps = [.clearFocusedField]
            storage.withUnsafeBytes { bytes in
                let units = bytes.bindMemory(to: UInt16.self)
                var lower = 0
                while lower < unitCount {
                    var upper = min(lower + Self.batchSize, unitCount)
                    if upper < unitCount, (0xd800...0xdbff).contains(units[upper - 1]) { upper -= 1 }
                    steps.append(.unicode(lower..<upper))
                    lower = upper
                }
            }
            steps.append(.submitReturn)
        } catch {
            erase()
            throw error
        }
    }

    deinit {
        storage.resetBytes(in: 0..<storage.count)
    }

    func erase() {
        storage.resetBytes(in: 0..<storage.count)
        unitCount = 0
        steps.removeAll()
    }

    func withBatch<Result>(_ range: Range<Int>, _ body: (UnsafeBufferPointer<UInt16>) throws -> Result) throws -> Result {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= unitCount else {
            throw MacUnlockPlatformError.invalidPassword
        }
        return try storage.withUnsafeBytes { bytes in
            let units = bytes.bindMemory(to: UInt16.self)
            return try body(UnsafeBufferPointer(start: units.baseAddress!.advanced(by: range.lowerBound), count: range.count))
        }
    }

    private static func nextScalar(in bytes: UnsafeBufferPointer<UInt8>, cursor: inout Int) throws -> UInt32 {
        let first = bytes[cursor]
        let count: Int
        let minimum: UInt32
        var value: UInt32
        switch first {
        case 0...0x7f: count = 1; minimum = 0; value = UInt32(first)
        case 0xc2...0xdf: count = 2; minimum = 0x80; value = UInt32(first & 0x1f)
        case 0xe0...0xef: count = 3; minimum = 0x800; value = UInt32(first & 0x0f)
        case 0xf0...0xf4: count = 4; minimum = 0x10000; value = UInt32(first & 0x07)
        default: throw MacUnlockPlatformError.invalidPassword
        }
        guard cursor + count <= bytes.count else { throw MacUnlockPlatformError.invalidPassword }
        for offset in 1..<count {
            let continuation = bytes[cursor + offset]
            guard continuation & 0xc0 == 0x80 else { throw MacUnlockPlatformError.invalidPassword }
            value = (value << 6) | UInt32(continuation & 0x3f)
        }
        guard value >= minimum, value <= 0x10ffff, !(0xd800...0xdfff).contains(value) else {
            throw MacUnlockPlatformError.invalidPassword
        }
        cursor += count
        return value
    }
}

@MainActor
final class SystemMacUnlockPlatform: MacUnlockPlatform {
    private struct Destination {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
        let field: AXUIElement
    }

    private static let executablePath = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"
    private var isSubmitting = false

    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    private let logger = Logger(subsystem: "com.local.Notchy", category: "MacUnlock")
    private var lastReportedState: MacUnlockScreenState?

    var screenState: MacUnlockScreenState {
        let state = MacUnlockSessionParser.parse(
            CGSessionCopyCurrentDictionary() as? [String: Any], ownUserID: geteuid(),
            protectedDataAvailable: NSApp?.isProtectedDataAvailable ?? false,
            securitySession: .current()
        )
        if state != lastReportedState {
            lastReportedState = state
            let label = switch state {
            case .locked: "locked"
            case .unlocked: "unlocked"
            case .unavailable: "unavailable"
            }
            logger.info("Mac unlock screen state: \(label, privacy: .public)")
        }
        return state
    }

    func submit(password: Data, for session: MacUnlockSession, stillValid: @escaping @MainActor () -> Bool) async throws {
        guard !isSubmitting else { throw MacUnlockPlatformError.submissionInProgress }
        isSubmitting = true
        defer { isSubmitting = false }
        let plan = try MacUnlockPasswordPlan(password: password)
        defer { plan.erase() }
        try validateSession(session, stillValid: stillValid)
        let destination = try focusedDestination()
        guard let source = CGEventSource(stateID: .privateState) else { throw MacUnlockPlatformError.eventCreationFailed }
        let access = MacUnlockFieldAccess(
            validate: { try self.validate(destination, session: session, stillValid: stillValid) },
            count: { try self.characterCount(destination.field) },
            selection: { try self.selectionRange(destination.field) },
            replaceWithEmptyValue: {
                try self.validate(destination, session: session, stillValid: stillValid)
                return try self.replaceWithEmptyValue(destination.field)
            },
            clearWithEditingKeys: {
                try await self.postKey(0x7c, flags: .maskCommand, destination: destination, source: source, session: session, stillValid: stillValid)
                try await self.postKey(0x33, flags: .maskCommand, destination: destination, source: source, session: session, stillValid: stillValid)
            },
            typeBatch: { range in
                try await self.postKey(0, destination: destination, source: source, session: session, stillValid: stillValid) { event in
                    try plan.withBatch(range) { units in
                        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units.baseAddress!)
                    }
                }
            },
            pressReturn: {
                try self.postReturn(destination: destination, source: source, session: session, stillValid: stillValid)
            }
        )
        do {
            try await MacUnlockFieldWriter(access: access).write(plan)
            logger.info("Mac unlock secure-field input accepted; awaiting session unlock")
        } catch let error as MacUnlockPlatformError {
            // These fixed error labels contain no field contents or credential lengths.
            logger.error("Mac unlock secure-field operation failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func validateSession(_ session: MacUnlockSession, stillValid: @MainActor () -> Bool) throws {
        guard !Task.isCancelled, stillValid() else { throw MacUnlockPlatformError.cancelled }
        guard accessibilityGranted else { throw MacUnlockPlatformError.accessibilityRequired }
        guard screenState == .locked(session) else { throw MacUnlockPlatformError.sessionChanged }
    }

    private func validate(_ destination: Destination, session: MacUnlockSession, stillValid: @MainActor () -> Bool) throws {
        try validateSession(session, stillValid: stillValid)
        let current = try focusedDestination()
        guard current.pid == destination.pid, current.startSeconds == destination.startSeconds,
              current.startMicroseconds == destination.startMicroseconds,
              CFEqual(current.field, destination.field) else { throw MacUnlockPlatformError.destinationChanged }
    }

    private func focusedDestination() throws -> Destination {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let field = element(system, attribute: kAXFocusedUIElementAttribute) else {
            throw MacUnlockPlatformError.destinationUnavailable
        }
        AXUIElementSetMessagingTimeout(field, 0.15)
        guard string(field, attribute: kAXRoleAttribute) == kAXTextFieldRole as String,
              string(field, attribute: kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String,
              boolean(field, attribute: kAXEnabledAttribute) == true,
              boolean(field, attribute: kAXFocusedAttribute) == true else {
            throw MacUnlockPlatformError.destinationUnavailable
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(field, &pid) == .success, pid > 0,
              let process = NSRunningApplication(processIdentifier: pid), !process.isTerminated,
              process.executableURL?.standardizedFileURL.path == Self.executablePath,
              process.bundleIdentifier == "com.apple.loginwindow" else { throw MacUnlockPlatformError.destinationUnavailable }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else {
            throw MacUnlockPlatformError.destinationUnavailable
        }
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            throw MacUnlockPlatformError.destinationUnavailable
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let appField = element(application, attribute: kAXFocusedUIElementAttribute), CFEqual(field, appField) else {
            throw MacUnlockPlatformError.destinationUnavailable
        }
        return Destination(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec, field: field)
    }

    private func replaceWithEmptyValue(_ field: AXUIElement) throws -> Bool {
        var settable = DarwinBoolean(false)
        let capability = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable)
        if capability == .attributeUnsupported { return false }
        guard capability == .success else { throw MacUnlockPlatformError.fieldCannotBeCleared }
        guard settable.boolValue else { return false }
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString) == .success else {
            throw MacUnlockPlatformError.fieldCannotBeCleared
        }
        return true
    }

    /// Return can immediately destroy the secure field as the desktop opens. Queue
    /// its down/up pair together after the final destination check; checking that
    /// field again after key-down would misreport a successful unlock as failure.
    /// Password batches still validate before each event. The controller independently
    /// waits for the original session to unlock before reporting success.
    private func postReturn(
        destination: Destination, source: CGEventSource, session: MacUnlockSession,
        stillValid: @MainActor () -> Bool
    ) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            throw MacUnlockPlatformError.eventCreationFailed
        }
        down.flags = []
        up.flags = []
        try validate(destination, session: session, stillValid: stillValid)
        down.postToPid(destination.pid)
        up.postToPid(destination.pid)
        logger.info("Mac unlock Return dispatched to the verified system field")
    }

    private func postKey(
        _ key: CGKeyCode, flags: CGEventFlags = [], destination: Destination, source: CGEventSource,
        session: MacUnlockSession, stillValid: @escaping @MainActor () -> Bool,
        configure: ((CGEvent) throws -> Void)? = nil
    ) async throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw MacUnlockPlatformError.eventCreationFailed
        }
        let zeros = [UInt16](repeating: 0, count: MacUnlockPasswordPlan.batchSize)
        defer {
            zeros.withUnsafeBufferPointer { down.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!) }
        }
        down.flags = flags
        up.flags = flags
        try configure?(down)
        try validate(destination, session: session, stillValid: stillValid)
        down.postToPid(destination.pid)
        try await Task.sleep(for: .milliseconds(8))
        try validate(destination, session: session, stillValid: stillValid)
        up.postToPid(destination.pid)
        try await Task.sleep(for: .milliseconds(8))
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ owner: AXUIElement, attribute name: String) -> AXUIElement? {
        guard let value = attribute(owner, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func string(_ owner: AXUIElement, attribute name: String) -> String? { attribute(owner, name) as? String }
    private func boolean(_ owner: AXUIElement, attribute name: String) -> Bool? { MacUnlockSessionParser.boolean(attribute(owner, name)) }
    private func characterCount(_ field: AXUIElement) throws -> Int? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(field, kAXNumberOfCharactersAttribute as CFString, &value)
        if status == .attributeUnsupported { return nil }
        guard status == .success, let count = MacUnlockSessionParser.unsignedInteger(value) else {
            throw MacUnlockPlatformError.inputNotAccepted
        }
        return Int(count)
    }

    private func selectionRange(_ field: AXUIElement) throws -> Range<Int>? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &value)
        if status == .attributeUnsupported { return nil }
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            throw MacUnlockPlatformError.inputNotAccepted
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0,
              range.location <= Int.max - range.length else {
            throw MacUnlockPlatformError.inputNotAccepted
        }
        return range.location..<(range.location + range.length)
    }
}
