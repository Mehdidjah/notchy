import Foundation

/// One Focus mode as described in `~/Library/DoNotDisturb/DB/ModeConfigurations.json`.
struct FocusModeConfiguration: Equatable, Sendable {
    var name: String
    var identifier: String
    var symbolName: String?
    var tintColorName: String?
}

/// What the Focus assertions file says right now.
struct FocusAssertionsReading: Equatable, Sendable {
    var isActive: Bool
    var identifier: String?
    var name: String?

    static let inactive = FocusAssertionsReading(isActive: false, identifier: nil, name: nil)
}

/// Mode metadata found in a Focus notification or a log line.
struct FocusMetadata: Equatable, Sendable {
    var identifier: String?
    var name: String?

    var isEmpty: Bool { identifier == nil && name == nil }
}

/// The Focus database macOS keeps under ~/Library/DoNotDisturb/DB. Reading it is a plain file
/// read that only succeeds with Full Disk Access; without it every read fails quietly. Nothing
/// here asks for access: Full Disk Access cannot be requested by an app, only granted by the
/// user in System Settings.
enum FocusDatabase {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    }

    static var assertionsURL: URL { directory.appendingPathComponent("Assertions.json") }
    static var modeConfigurationsURL: URL { directory.appendingPathComponent("ModeConfigurations.json") }

    /// True when a file protected by Full Disk Access can be opened.
    static func hasFullDiskAccess() -> Bool {
        let probes = [
            modeConfigurationsURL,
            assertionsURL,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        ]
        return probes.contains { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let handle = try? FileHandle(forReadingFrom: url)
            else { return false }
            try? handle.close()
            return true
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - Assertions.json

    /// Focus is on while `data[0].storeAssertionRecords` is non-empty. Returns nil for data that
    /// is not the expected JSON.
    static func parseAssertions(_ data: Data) -> FocusAssertionsReading? {
        guard !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else { return nil }
        guard let first = entries.first else { return .inactive }
        let records = first["storeAssertionRecords"] as? [Any] ?? []
        guard !records.isEmpty else { return .inactive }
        let identifier = FocusPayloadSearch.firstString(for: FocusPayloadSearch.modeIdentifierKeys, in: records)
            ?? FocusPayloadSearch.firstString(
                for: FocusPayloadSearch.genericIdentifierKeys, in: records, where: FocusPayloadSearch.looksLikeModeIdentifier
            )
        let name = FocusPayloadSearch.firstString(for: FocusPayloadSearch.nameKeys, in: records)
        return FocusAssertionsReading(isActive: true, identifier: identifier, name: name)
    }

    // MARK: - ModeConfigurations.json

    static func parseModeConfigurations(_ data: Data) -> [FocusModeConfiguration] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else { return [] }
        var result: [FocusModeConfiguration] = []
        for entry in entries {
            guard let configurations = entry["modeConfigurations"] as? [String: Any] else { continue }
            for key in configurations.keys.sorted() {
                guard let wrapper = configurations[key] as? [String: Any],
                      let mode = wrapper["mode"] as? [String: Any],
                      let name = mode["name"] as? String,
                      let identifier = mode["modeIdentifier"] as? String
                else { continue }
                result.append(FocusModeConfiguration(
                    name: name,
                    identifier: identifier,
                    symbolName: mode["symbolImageName"] as? String,
                    tintColorName: mode["tintColorName"] as? String
                ))
            }
        }
        return result
    }

    /// The configuration for a mode, matched by identifier first, then by name.
    static func configuration(
        in configurations: [FocusModeConfiguration],
        identifier: String?,
        name: String?
    ) -> FocusModeConfiguration? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let identifier, !identifier.isEmpty,
           let match = configurations.first(where: { $0.identifier.compare(identifier, options: options) == .orderedSame }) {
            return match
        }
        if let name, !name.isEmpty,
           let match = configurations.first(where: { $0.name.compare(name, options: options) == .orderedSame }) {
            return match
        }
        return nil
    }
}

/// Key and pattern search through loosely structured Focus payloads.
enum FocusPayloadSearch {
    /// Keys that name the active mode itself.
    static let modeIdentifierKeys = [
        "assertionDetailsModeIdentifier", "modeIdentifier", "FocusModeIdentifier", "focusModeIdentifier",
        "semanticModeIdentifier", "activeModeIdentifier"
    ]
    /// Broader keys, accepted only for values that look like a Focus identifier.
    static let genericIdentifierKeys = [
        "identifier", "Identifier", "FocusModeUUID", "focusModeUUID", "UUID", "uuid"
    ]
    static let nameKeys = [
        "activityDisplayName", "displayName", "display_name", "FocusModeName", "focusModeName",
        "FocusMode", "focusMode", "name", "Name"
    ]

    static func looksLikeModeIdentifier(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("com.apple.focus") || lower.hasPrefix("com.apple.donotdisturb")
            || lower.hasPrefix("com.apple.sleep")
    }

    /// Depth-first search for the first string under any of `keys`, checking each dictionary's
    /// own keys (in `keys` order) before descending, and children in sorted key order.
    static func firstString(
        for keys: [String],
        in value: Any,
        where accept: (String) -> Bool = { _ in true }
    ) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let string = dictionary[key] as? String {
                    let cleaned = cleaned(string)
                    if !cleaned.isEmpty, accept(cleaned) { return cleaned }
                }
            }
            for key in dictionary.keys.sorted() {
                if let nested = dictionary[key], let found = firstString(for: keys, in: nested, where: accept) {
                    return found
                }
            }
        } else if let dictionary = value as? [AnyHashable: Any] {
            var bridged: [String: Any] = [:]
            for (key, nested) in dictionary { bridged[String(describing: key)] = nested }
            return firstString(for: keys, in: bridged, where: accept)
        } else if let array = value as? [Any] {
            for element in array {
                if let found = firstString(for: keys, in: element, where: accept) { return found }
            }
        } else if let data = value as? Data, let decoded = decode(data) {
            return firstString(for: keys, in: decoded, where: accept)
        }
        return nil
    }

    static func cleaned(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    /// Property-list or JSON payloads that some senders wrap in `Data`.
    static func decode(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) { return plist }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: Free text (notification descriptions, log lines)

    private static let identifierPattern = #"com\.apple\.(?:focus|donotdisturb|sleep)[A-Za-z0-9_.-]*"#
    private static let identifierDetailPatterns = [
        #"modeIdentifier:\s*'([^'\s]+)'"#,
        #"activityIdentifier:\s*([A-Za-z0-9._-]+)"#,
        #"semanticModeIdentifier:\s*([A-Za-z0-9._-]+)"#
    ]
    private static let namePatterns = [
        #"(?i)(?:focusModeName|focusMode|displayName|name)\s*=\s*"([^"]+)""#,
        #"(?i)(?:focusModeName|focusMode|displayName|name)\s*=\s*([^;\n]+)"#,
        #"activityDisplayName:\s*([^;>\n]+)"#,
        #"semanticType:\s*([A-Za-z][A-Za-z0-9 _-]+)"#,
        #"modeIdentifier:\s*'com\.apple\.focus\.([A-Za-z0-9._-]+)'"#
    ]

    static func identifier(inText text: String) -> String? {
        if let match = firstMatch(of: identifierPattern, in: text, group: 0) { return match }
        for pattern in identifierDetailPatterns {
            if let match = firstMatch(of: pattern, in: text, group: 1) { return match }
        }
        return nil
    }

    static func name(inText text: String) -> String? {
        for pattern in namePatterns {
            if let match = firstMatch(of: pattern, in: text, group: 1) { return match }
        }
        return nil
    }

    private static func firstMatch(of pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let found = Range(match.range(at: group), in: text)
        else { return nil }
        let value = cleaned(String(text[found]))
        return value.isEmpty ? nil : value
    }

    // MARK: Notifications

    /// Pulls a mode identifier and name out of a Focus notification's user info and object.
    static func metadata(userInfo: [AnyHashable: Any]?, object: Any?) -> FocusMetadata {
        var candidates: [Any] = []
        if let userInfo { candidates.append(userInfo) }
        if let object { candidates.append(object) }

        var identifier: String?
        var name: String?
        for candidate in candidates {
            identifier = identifier
                ?? firstString(for: modeIdentifierKeys, in: candidate)
                ?? firstString(for: genericIdentifierKeys, in: candidate, where: looksLikeModeIdentifier)
            name = name ?? firstString(for: nameKeys, in: candidate)
        }
        if identifier == nil || name == nil {
            for candidate in candidates {
                let text = String(describing: candidate)
                identifier = identifier ?? self.identifier(inText: text)
                name = name ?? self.name(inText: text)
            }
        }
        return FocusMetadata(identifier: identifier, name: name)
    }

    // MARK: Unified log

    enum LogEvent: Equatable, Sendable {
        /// The log says no mode is active.
        case cleared
        case metadata(FocusMetadata)
    }

    /// Reads one compact-style line from duetexpertd or donotdisturbd.
    static func logEvent(fromLine line: String) -> LogEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("Filtering the log data"),
              !trimmed.hasPrefix("Timestamp")
        else { return nil }
        if trimmed.contains("active mode assertion: (null)") || trimmed.contains("activeModeIdentifier: (null)") {
            return .cleared
        }
        var identifier: String?
        var name: String?
        if trimmed.contains("<DNDMode:") {
            identifier = field("modeIdentifier:", in: trimmed)
            name = field("name:", in: trimmed)
        }
        identifier = identifier ?? self.identifier(inText: trimmed)
        name = name ?? self.name(inText: trimmed)
        let metadata = FocusMetadata(identifier: identifier, name: name)
        return metadata.isEmpty ? nil : .metadata(metadata)
    }

    private static func field(_ key: String, in text: String) -> String? {
        guard let start = text.range(of: key) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: ";") else { return nil }
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
