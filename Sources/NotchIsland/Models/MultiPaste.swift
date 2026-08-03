import Foundation

enum MultiPasteSeparator: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case space
    case newLine
    case blankLine
    case commaSpace
    case bulletList
    case numberedList
    case custom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: "None"
        case .space: "Space"
        case .newLine: "New line"
        case .blankLine: "Blank line"
        case .commaSpace: "Comma"
        case .bulletList: "Bullets"
        case .numberedList: "Numbered"
        case .custom: "Custom"
        }
    }
}

enum MultiPasteOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserveFormatting
    case plainText
    case markdown
    case oneItemPerLine

    var id: Self { self }

    var displayName: String {
        switch self {
        case .preserveFormatting: "Preserve"
        case .plainText: "Plain text"
        case .markdown: "Markdown"
        case .oneItemPerLine: "Lines"
        }
    }
}

struct MultiPasteComposer: Sendable {
    func combine(
        clips: [Clip],
        separator: MultiPasteSeparator,
        outputFormat: MultiPasteOutputFormat,
        customSeparator: String = ""
    ) -> String {
        let values = clips.map(\.value)
        guard !values.isEmpty else { return "" }

        if outputFormat == .oneItemPerLine {
            return values.joined(separator: "\n")
        }
        if separator == .bulletList {
            return values.map { "- \($0)" }.joined(separator: "\n")
        }
        if separator == .numberedList {
            return values.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
        if outputFormat == .markdown, values.count > 1 {
            return values.map { "- \($0)" }.joined(separator: "\n")
        }

        let joiner: String = switch separator {
        case .none: ""
        case .space: " "
        case .newLine: "\n"
        case .blankLine: "\n\n"
        case .commaSpace: ", "
        case .bulletList, .numberedList: "\n"
        case .custom: customSeparator
        }
        return values.joined(separator: joiner)
    }
}

struct SequentialPasteQueue: Equatable, Sendable {
    private(set) var clipIDs: [UUID] = []
    private(set) var currentIndex = 0
    private(set) var isActive = false

    var currentClipID: UUID? {
        guard isActive, clipIDs.indices.contains(currentIndex) else { return nil }
        return clipIDs[currentIndex]
    }

    var remainingCount: Int {
        guard isActive else { return 0 }
        return max(0, clipIDs.count - currentIndex)
    }

    var positionDescription: String {
        guard isActive, !clipIDs.isEmpty else { return "Queue inactive" }
        return "\(currentIndex + 1) of \(clipIDs.count)"
    }

    mutating func start(with clips: [Clip]) {
        clipIDs = clips.map(\.id)
        currentIndex = 0
        isActive = !clipIDs.isEmpty
    }

    @discardableResult
    mutating func advance() -> UUID? {
        guard let current = currentClipID else { return nil }
        currentIndex += 1
        if currentIndex >= clipIDs.count { isActive = false }
        return current
    }

    mutating func movePrevious() {
        guard !clipIDs.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        isActive = true
    }

    mutating func skip() {
        guard isActive else { return }
        currentIndex += 1
        if currentIndex >= clipIDs.count { isActive = false }
    }

    mutating func restart() {
        currentIndex = 0
        isActive = !clipIDs.isEmpty
    }

    mutating func cancel() {
        clipIDs.removeAll()
        currentIndex = 0
        isActive = false
    }
}

struct ClipGroup: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var systemImage: String
    var childClipIDs: [UUID]
    var separator: MultiPasteSeparator
    var outputFormat: MultiPasteOutputFormat
    var categoryIdentifier: String?
    var collectionIdentifier: UUID?
    var inlineShortcut: String?
}
