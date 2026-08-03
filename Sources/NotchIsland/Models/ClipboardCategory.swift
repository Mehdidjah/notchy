import Foundation

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case history = "History"
    case all = "All"
    case favorites = "Favorites"
    case pinned = "Pinned"
    case text = "Text"
    case images = "Images"
    case files = "Files"
    case links = "Links"
    case code = "Code"
    case colors = "Colors"
    case screenshots = "Screenshots"

    var id: Self { self }
}
