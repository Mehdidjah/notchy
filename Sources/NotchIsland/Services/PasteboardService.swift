import AppKit

@MainActor
protocol PasteboardWriting {
    @discardableResult
    func copy(_ value: String) -> Bool
}

@MainActor
final class PasteboardService: PasteboardWriting {
    var onInternalWrite: ((Int) -> Void)?

    @discardableResult
    func copy(_ value: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let succeeded = pasteboard.setString(value, forType: .string)
        if succeeded { onInternalWrite?(pasteboard.changeCount) }
        return succeeded
    }
}
