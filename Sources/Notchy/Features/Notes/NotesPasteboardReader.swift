import AppKit
import Foundation

/// What the pasteboard offers a note.
enum NotesPasteboardContent: Equatable, Sendable {
    case image(Data)
    case text(String)
}

/// Reads the general pasteboard for notes: an image file first (the original
/// beats a Finder icon), then TIFF or PNG data, then plain text.
@MainActor
enum NotesPasteboardReader {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"
    ]

    static func read(from pasteboard: NSPasteboard = .general) -> NotesPasteboardContent? {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if let imageURL = fileURLs.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
           let data = try? Data(contentsOf: imageURL) {
            return .image(data)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return .image(tiff)
        }
        if let png = pasteboard.data(forType: .png) {
            return .image(png)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    /// True when the pasteboard holds a picture, so a paste inside a text field should attach
    /// it to the note instead of inserting text.
    static func containsImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if fileURLs.contains(where: { imageExtensions.contains($0.pathExtension.lowercased()) }) {
            return true
        }
        let types = pasteboard.types ?? []
        return types.contains(.tiff) || types.contains(.png)
    }

    /// Copies a note's body, and its picture as TIFF, to the general pasteboard.
    static func copy(text: String, imageData: Data?, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let imageData, let tiff = NSImage(data: imageData)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
