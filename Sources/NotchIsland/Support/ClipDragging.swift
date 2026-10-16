import AppKit
import UniformTypeIdentifiers

extension Clip {
    /// Builds the payload handed to another app when a card is dragged out of the island.
    ///
    /// Files travel as file URLs so Finder receives real files. Links travel as URLs with a
    /// plain-text fallback, and everything else as text, so a drop into a text field always
    /// resolves. The provider is built from the clip's metadata only; large binary payloads
    /// stay on disk and are not loaded for the drag.
    func dragItemProvider() -> NSItemProvider {
        if let first = originalFileURLs.first, originalFileURLs.count == 1,
           let provider = NSItemProvider(contentsOf: first) {
            return provider
        }
        if let url = urlValue {
            let provider = NSItemProvider(object: url as NSURL)
            let text = url.absoluteString
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(Data(text.utf8), nil)
                return nil
            }
            return provider
        }
        let text = value.isEmpty ? title : value
        return NSItemProvider(object: text as NSString)
    }

    /// A multi-file clip cannot ride a single drag provider; those cards are not draggable.
    var isDraggable: Bool {
        originalFileURLs.count <= 1 && !(value.isEmpty && title.isEmpty)
    }
}
