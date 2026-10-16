import Foundation
import SwiftUI

/// A colour-coded sticky note shown in the Notes tab.
///
/// Notes are stored together as JSON; a note's picture, when it has one, is a PNG file next
/// to that JSON and is referenced here by file name only.
struct NoteItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var creationDate: Date
    var modificationDate: Date
    /// Index into `NoteItem.palette`: yellow, blue, red, green, purple, orange.
    var colorIndex: Int
    var isPinned: Bool
    var imageFileName: String?
    /// The Apple Notes identifier of the linked note while Apple Notes sync is on.
    var appleNotesID: String?

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        creationDate: Date = Date(),
        modificationDate: Date? = nil,
        colorIndex: Int = 0,
        isPinned: Bool = false,
        imageFileName: String? = nil,
        appleNotesID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.creationDate = creationDate
        self.modificationDate = modificationDate ?? creationDate
        self.colorIndex = colorIndex
        self.isPinned = isPinned
        self.imageFileName = imageFileName
        self.appleNotesID = appleNotesID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, creationDate, modificationDate, colorIndex, isPinned, imageFileName, appleNotesID
    }

    /// Older or hand-edited files may miss the optional fields; fill them with sensible values.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        creationDate = try values.decodeIfPresent(Date.self, forKey: .creationDate) ?? Date()
        modificationDate = try values.decodeIfPresent(Date.self, forKey: .modificationDate) ?? creationDate
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        imageFileName = try values.decodeIfPresent(String.self, forKey: .imageFileName)
        appleNotesID = try values.decodeIfPresent(String.self, forKey: .appleNotesID)
    }

    // MARK: - Presentation

    /// Title given to a note saved without one.
    static let untitledTitle = "Untitled Note"

    /// The six note colours, in the order the editor offers them.
    static let palette: [Color] = [.yellow, .blue, .red, .green, .purple, .orange]
    static let paletteNames = ["Yellow", "Blue", "Red", "Green", "Purple", "Orange"]

    static func color(at index: Int) -> Color {
        palette.indices.contains(index) ? palette[index] : .yellow
    }

    var color: Color { Self.color(at: colorIndex) }

    /// Second line of a row: the body, or a placeholder when the note has none.
    var previewText: String { content.isEmpty ? "No content" : content }

    /// File name used for a note's picture.
    static func imageFileName(for id: UUID) -> String {
        "note_image_\(id.uuidString).png"
    }

    /// The title to store for a draft: blank titles become "Untitled Note".
    static func resolvedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? untitledTitle : title
    }
}

/// Sorting and filtering shared by the list, the store and Apple Notes merging.
enum NoteOrdering {
    /// Pinned notes first, then the most recently modified.
    static func sorted(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.modificationDate != rhs.modificationDate { return lhs.modificationDate > rhs.modificationDate }
            if lhs.creationDate != rhs.creationDate { return lhs.creationDate > rhs.creationDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Notes whose title or body contains `query` (case- and diacritic-insensitive), limited
    /// to one colour when `colorIndex` is set. Keeps the incoming order.
    static func filtered(_ notes: [NoteItem], query: String, colorIndex: Int?) -> [NoteItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            if let colorIndex, note.colorIndex != colorIndex { return false }
            guard !needle.isEmpty else { return true }
            return note.title.localizedStandardContains(needle) || note.content.localizedStandardContains(needle)
        }
    }

    /// Compact "time ago" label used on list rows: Just now, 5m, 3h, then the day and month.
    static func timeAgo(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        return date.formatted(.dateTime.day().month())
    }
}
