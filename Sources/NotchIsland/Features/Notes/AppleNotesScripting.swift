import Foundation

/// A note read from the Notes app.
struct RemoteAppleNote: Equatable, Sendable {
    let id: String
    let title: String
    let content: String
    let creationDate: Date
    let modificationDate: Date
    /// The island note this one was created from, read from the marker in its body.
    let linkedNoteID: UUID?
}

/// What is written to the Notes app for one island note.
struct AppleNotesPayload: Equatable, Sendable {
    let noteID: UUID
    let title: String
    let content: String
}

enum AppleNotesSyncError: LocalizedError, Equatable {
    case automationDenied
    case notesUnavailable
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Allow NotchIsland to control Notes in System Settings → Privacy & Security → Automation."
        case .notesUnavailable:
            "The Notes app could not be reached."
        case .scriptFailed(let message):
            message
        }
    }
}

/// The Notes app operations sync needs. The live implementation drives Notes with AppleScript;
/// tests substitute an in-memory one.
protocol AppleNotesScripting: Sendable {
    func fetchNotes(scope: AppleNotesSyncScope) async throws -> [RemoteAppleNote]
    /// Creates a note in the NotchIsland folder and returns its Notes identifier.
    func createNote(_ payload: AppleNotesPayload) async throws -> String
    /// Rewrites a note; returns false when the note no longer exists.
    func updateNote(id: String, with payload: AppleNotesPayload) async throws -> Bool
    func deleteNote(id: String) async throws
}

/// Drives the Notes app with `NSAppleScript` on a private serial queue, one script at a time,
/// so the main thread never waits for Notes to launch or answer.
final class OSAAppleNotesScripting: AppleNotesScripting {
    static let folderName = "NotchIsland"
    /// U+241F SYMBOL FOR UNIT SEPARATOR and U+241E SYMBOL FOR RECORD SEPARATOR.
    static let fieldSeparator: Character = "\u{241F}"
    static let recordSeparator: Character = "\u{241E}"
    static let markerPrefix = "notchisland:id="

    private let queue = DispatchQueue(label: "NotchIsland.notes.applescript", qos: .userInitiated)

    init() {}

    func fetchNotes(scope: AppleNotesSyncScope) async throws -> [RemoteAppleNote] {
        let output = try await run(Self.fetchScript(scope: scope))
        return Self.parseRecords(output)
    }

    func createNote(_ payload: AppleNotesPayload) async throws -> String {
        let id = try await run(Self.createScript(payload))
        guard !id.isEmpty else { throw AppleNotesSyncError.scriptFailed("Notes did not return the new note.") }
        return id
    }

    func updateNote(id: String, with payload: AppleNotesPayload) async throws -> Bool {
        try await run(Self.updateScript(id: id, payload: payload)) != "missing"
    }

    func deleteNote(id: String) async throws {
        _ = try await run(Self.deleteScript(id: id))
    }

    private func run(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: AppleNotesSyncError.scriptFailed("The Notes script could not be prepared."))
                    return
                }
                var errorInfo: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    continuation.resume(throwing: Self.error(from: errorInfo))
                    return
                }
                let text = descriptor.stringValue ?? ""
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func error(from info: NSDictionary) -> AppleNotesSyncError {
        let number = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        switch number {
        case -1743:
            return .automationDenied
        case -600, -609:
            return .notesUnavailable
        default:
            let message = info[NSAppleScript.errorMessage] as? String
            return .scriptFailed(message ?? "The Notes script failed (\(number ?? 0)).")
        }
    }

    // MARK: - Scripts

    /// AppleScript string literal for `value`.
    static func literal(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\r", "\n", "\u{2028}", "\u{2029}": result += "\\n"
            case "\t": result += "\\t"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Notes body for an island note: the title as the first (heading) line, one `<div>` per
    /// line of text, then a hidden marker that links the copy back to the island note.
    static func htmlBody(for payload: AppleNotesPayload) -> String {
        let title = NoteItem.resolvedTitle(payload.title)
        let lines = payload.content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var html = "<div><h1>\(escapeHTML(title))</h1></div>"
        if !payload.content.isEmpty {
            for line in lines {
                html += line.isEmpty ? "<div><br></div>" : "<div>\(escapeHTML(String(line)))</div>"
            }
        }
        return html + "<!--\(markerPrefix)\(payload.noteID.uuidString)-->"
    }

    static func fetchScript(scope: AppleNotesSyncScope) -> String {
        let folder = literal(folderName)
        let source: String
        let prepare: String
        switch scope {
        case .allNotes:
            source = "every note of default account"
            prepare = ""
        case .notchIslandFolder:
            source = "every note of folder \(folder) of default account"
            prepare = """
                    if not (exists folder \(folder) of default account) then
                        make new folder at default account with properties {name:\(folder)}
                    end if
            """
        }
        return """
        on run
            set fieldSep to character id 9247
            set recordSep to character id 9246
            set noteRecords to {}
            tell application "Notes"
        \(prepare)
                repeat with aNote in (\(source))
                    set isDeleted to false
                    try
                        if (name of container of aNote) is "Recently Deleted" then set isDeleted to true
                    end try
                    if password protected of aNote is false and isDeleted is false then
                        set noteLine to (id of aNote) & fieldSep & my scrub(name of aNote, fieldSep, recordSep)
                        set noteLine to noteLine & fieldSep & my stamp(creation date of aNote)
                        set noteLine to noteLine & fieldSep & my stamp(modification date of aNote)
                        set noteLine to noteLine & fieldSep & my scrub(plaintext of aNote, fieldSep, recordSep)
                        set noteLine to noteLine & fieldSep & my markerOf(body of aNote)
                        set end of noteRecords to noteLine
                    end if
                end repeat
            end tell
            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to recordSep
            set joined to noteRecords as text
            set AppleScript's text item delimiters to savedDelimiters
            return joined
        end run

        on stamp(aDate)
            return ((year of aDate) as integer as text) & "-" & ((month of aDate) as integer as text) & "-" & ((day of aDate) as integer as text) & "-" & ((time of aDate) as integer as text)
        end stamp

        on scrub(someText, fieldSep, recordSep)
            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to fieldSep
            set pieces to text items of someText
            set AppleScript's text item delimiters to " "
            set someText to pieces as text
            set AppleScript's text item delimiters to recordSep
            set pieces to text items of someText
            set AppleScript's text item delimiters to " "
            set someText to pieces as text
            set AppleScript's text item delimiters to savedDelimiters
            return someText
        end scrub

        on markerOf(bodyText)
            set markerText to "\(markerPrefix)"
            if bodyText does not contain markerText then return ""
            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to markerText
            set tailText to text item 2 of bodyText
            set AppleScript's text item delimiters to "-->"
            set foundID to text item 1 of tailText
            set AppleScript's text item delimiters to savedDelimiters
            return foundID
        end markerOf
        """
    }

    static func createScript(_ payload: AppleNotesPayload) -> String {
        let folder = literal(folderName)
        return """
        tell application "Notes"
            if not (exists folder \(folder) of default account) then
                make new folder at default account with properties {name:\(folder)}
            end if
            set newNote to make new note at folder \(folder) of default account with properties {body:\(literal(htmlBody(for: payload)))}
            return id of newNote
        end tell
        """
    }

    static func updateScript(id: String, payload: AppleNotesPayload) -> String {
        """
        tell application "Notes"
            set matches to (every note whose id is \(literal(id)))
            if (count of matches) is 0 then return "missing"
            set body of item 1 of matches to \(literal(htmlBody(for: payload)))
            return "ok"
        end tell
        """
    }

    static func deleteScript(id: String) -> String {
        """
        tell application "Notes"
            set matches to (every note whose id is \(literal(id)))
            if (count of matches) > 0 then delete item 1 of matches
            return "ok"
        end tell
        """
    }

    // MARK: - Parsing

    /// Splits the fetch script's output into notes. Each record is
    /// `id ␟ name ␟ created ␟ modified ␟ plain text ␟ marker`, records joined by ␞.
    static func parseRecords(_ output: String, timeZone: TimeZone = .current) -> [RemoteAppleNote] {
        guard !output.isEmpty else { return [] }
        return output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { record -> RemoteAppleNote? in
                let fields = record.split(separator: fieldSeparator, maxSplits: 5, omittingEmptySubsequences: false)
                guard fields.count >= 5,
                      let created = parseStamp(String(fields[2]), timeZone: timeZone),
                      let modified = parseStamp(String(fields[3]), timeZone: timeZone) else { return nil }
                let id = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return nil }
                let title = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let linked = fields.count > 5
                    ? UUID(uuidString: String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines))
                    : nil
                return RemoteAppleNote(
                    id: id,
                    title: title,
                    content: bodyText(fromPlainText: String(fields[4]), title: title),
                    creationDate: created,
                    modificationDate: modified,
                    linkedNoteID: linked
                )
            }
    }

    /// Notes repeats the title as the first line of a note's plain text; drop it.
    static func bodyText(fromPlainText plain: String, title: String) -> String {
        let normalized = plain
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let newline = normalized.firstIndex(of: "\n") else {
            return normalized.trimmingCharacters(in: .whitespaces) == title ? "" : normalized
        }
        let firstLine = normalized[..<newline].trimmingCharacters(in: .whitespaces)
        guard firstLine == title else { return normalized }
        return String(normalized[normalized.index(after: newline)...])
    }

    /// Parses `year-month-day-secondsSinceMidnight`, a wall-clock time in `timeZone`.
    static func parseStamp(_ raw: String, timeZone: TimeZone) -> Date? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let midnight = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .second, value: parts[3], to: midnight)
    }
}
