import Foundation

struct PasteboardRepresentation: Hashable, Sendable {
    let typeIdentifier: String
    let data: Data
}

struct ClipboardSource: Hashable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String?
}

struct ClipboardSnapshot: Hashable, Sendable {
    let changeCount: Int
    let capturedAt: Date
    let source: ClipboardSource
    let representations: [PasteboardRepresentation]
    let fileURLs: [URL]

    func representation(_ identifier: String) -> Data? {
        representations.first { $0.typeIdentifier == identifier }?.data
    }
}
