import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

enum PasteOutcome: Equatable, Sendable {
    case pasted
    case copiedOnly
    case failed(String)
}

@MainActor
protocol ClipPasteboardWriting: AnyObject {
    func write(_ clip: Clip, plainTextOnly: Bool) async throws -> Int
}

@MainActor
final class SystemClipPasteboardWriter: ClipPasteboardWriting {
    var onInternalWrite: ((Int) -> Void)?

    private let pasteboard: NSPasteboard
    private let payloadStore: PayloadStore

    init(pasteboard: NSPasteboard = .general, payloadStore: PayloadStore) {
        self.pasteboard = pasteboard
        self.payloadStore = payloadStore
    }

    func write(_ clip: Clip, plainTextOnly: Bool) async throws -> Int {
        let imageData: Data?
        if !plainTextOnly, let imagePath = clip.imagePayloadPath {
            imageData = try await payloadStore.data(at: imagePath)
        } else {
            imageData = nil
        }
        let richTextData: Data?
        if !plainTextOnly, let path = clip.richTextPayloadPath {
            richTextData = try await payloadStore.data(at: path)
        } else {
            richTextData = nil
        }
        let htmlData: Data?
        if !plainTextOnly, let path = clip.htmlPayloadPath {
            htmlData = try await payloadStore.data(at: path)
        } else {
            htmlData = nil
        }

        pasteboard.clearContents()
        let succeeded: Bool
        if !plainTextOnly, !clip.originalFileURLs.isEmpty {
            succeeded = pasteboard.writeObjects(clip.originalFileURLs as [NSURL])
        } else {
            let item = NSPasteboardItem()
            if let text = clip.plainText ?? clip.urlValue?.absoluteString {
                item.setString(text, forType: .string)
            }
            if let richTextData { item.setData(richTextData, forType: .rtf) }
            if let htmlData { item.setData(htmlData, forType: .html) }
            if let imageData {
                let imageType: NSPasteboard.PasteboardType = clip.imagePayloadPath?.hasSuffix(".png") == true
                    ? .png
                    : .tiff
                item.setData(imageData, forType: imageType)
            }
            succeeded = pasteboard.writeObjects([item])
        }
        guard succeeded else { throw PasteCoordinatorError.pasteboardWriteFailed }
        onInternalWrite?(pasteboard.changeCount)
        return pasteboard.changeCount
    }
}

enum PasteCoordinatorError: LocalizedError {
    case pasteboardWriteFailed
    case missingTargetApplication
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .pasteboardWriteFailed: "The clip could not be written to the clipboard."
        case .missingTargetApplication: "The target application is no longer available."
        case .eventCreationFailed: "macOS could not create the paste keyboard event."
        }
    }
}

@MainActor
protocol PasteCoordinating: AnyObject {
    func paste(_ clip: Clip, to application: NSRunningApplication?, plainTextOnly: Bool) async -> PasteOutcome
    func copy(_ clip: Clip, plainTextOnly: Bool) async -> PasteOutcome
}

@MainActor
final class PasteCoordinator: PasteCoordinating {
    private let pasteboardWriter: ClipPasteboardWriting
    private let accessibilityTrusted: () -> Bool

    init(
        pasteboardWriter: ClipPasteboardWriting,
        accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.pasteboardWriter = pasteboardWriter
        self.accessibilityTrusted = accessibilityTrusted
    }

    func copy(_ clip: Clip, plainTextOnly: Bool = false) async -> PasteOutcome {
        do {
            _ = try await pasteboardWriter.write(clip, plainTextOnly: plainTextOnly)
            return .copiedOnly
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func paste(
        _ clip: Clip,
        to application: NSRunningApplication?,
        plainTextOnly: Bool = false
    ) async -> PasteOutcome {
        do {
            _ = try await pasteboardWriter.write(clip, plainTextOnly: plainTextOnly)
            guard let application else { return .copiedOnly }
            guard accessibilityTrusted() else { return .copiedOnly }

            application.activate(options: [])
            try? await Task.sleep(for: .milliseconds(90))
            guard sendCommandV() else { throw PasteCoordinatorError.eventCreationFailed }
            return .pasted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func sendCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
