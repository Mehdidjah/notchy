import CryptoKit
import Foundation
import UniformTypeIdentifiers

actor ClipboardNormalizer {
    private let payloadStore: PayloadStore

    init(payloadStore: PayloadStore) {
        self.payloadStore = payloadStore
    }

    func normalize(_ snapshot: ClipboardSnapshot) async throws -> Clip? {
        guard !snapshot.representations.isEmpty || !snapshot.fileURLs.isEmpty else { return nil }

        let id = UUID()
        let plainText = decodedString(snapshot.representation(UTType.utf8PlainText.identifier))
            ?? decodedString(snapshot.representation(UTType.plainText.identifier))
            ?? decodedString(snapshot.representation("public.utf8-plain-text"))
        let richText = snapshot.representation(UTType.rtf.identifier)
        let html = snapshot.representation(UTType.html.identifier)
        let image = snapshot.representation(UTType.png.identifier)
            ?? snapshot.representation(UTType.tiff.identifier)
        let pdf = snapshot.representation(UTType.pdf.identifier)

        let type = classify(
            text: plainText,
            fileURLs: snapshot.fileURLs,
            hasRichText: richText != nil,
            hasHTML: html != nil,
            hasImage: image != nil,
            hasPDF: pdf != nil
        )
        let canonicalData = canonicalData(
            text: plainText,
            fileURLs: snapshot.fileURLs,
            richText: richText,
            html: html,
            image: image,
            pdf: pdf,
            allRepresentations: snapshot.representations
        )
        guard !canonicalData.isEmpty else { return nil }

        let richPath: String?
        if let richText {
            richPath = try await payloadStore.store(richText, clipID: id, fileExtension: "rtf")
        } else {
            richPath = nil
        }
        let htmlPath: String?
        if let html {
            htmlPath = try await payloadStore.store(html, clipID: id, fileExtension: "html")
        } else {
            htmlPath = nil
        }
        let imagePath: String?
        if let image {
            let fileExtension = snapshot.representation(UTType.png.identifier) != nil ? "png" : "tiff"
            imagePath = try await payloadStore.store(image, clipID: id, fileExtension: fileExtension)
        } else {
            imagePath = nil
        }
        let pdfPath: String?
        if let pdf {
            pdfPath = try await payloadStore.store(pdf, clipID: id, fileExtension: "pdf")
        } else {
            pdfPath = nil
        }

        let urlValue: URL? = type == .url
            ? plainText.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            : nil
        let detectedColors = type == .color ? [plainText ?? ""] : []
        let searchComponents = [
            plainText,
            urlValue?.absoluteString,
            snapshot.fileURLs.map(\.lastPathComponent).joined(separator: " "),
            snapshot.source.applicationName
        ].compactMap { $0 }

        return Clip(
            id: id,
            createdAt: snapshot.capturedAt,
            updatedAt: snapshot.capturedAt,
            lastCopiedAt: snapshot.capturedAt,
            originalSourceDate: snapshot.capturedAt,
            contentType: type,
            plainText: plainText,
            searchableText: searchComponents.joined(separator: "\n"),
            richTextPayloadPath: richPath,
            htmlPayloadPath: htmlPath,
            imagePayloadPath: imagePath ?? pdfPath,
            originalFileURLs: snapshot.fileURLs,
            copiedFilePaths: snapshot.fileURLs.map(\.path),
            urlValue: urlValue,
            detectedColors: detectedColors,
            sourceApplicationBundleIdentifier: snapshot.source.bundleIdentifier,
            sourceApplicationName: snapshot.source.applicationName,
            byteSize: Int64(canonicalData.count),
            contentHash: SHA256.hash(data: canonicalData).hexString,
            cardStyle: cardStyle(for: type)
        )
    }

    private func decodedString(_ data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }

    private func classify(
        text: String?,
        fileURLs: [URL],
        hasRichText: Bool,
        hasHTML: Bool,
        hasImage: Bool,
        hasPDF: Bool
    ) -> ClipType {
        if !fileURLs.isEmpty {
            if fileURLs.count > 1 { return .multipleFiles }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURLs[0].path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return .folder
            }
            return fileURLs[0].pathExtension.lowercased() == "pdf" ? .pdf : .file
        }
        if hasPDF { return .pdf }
        if hasImage { return .image }
        guard let text else {
            if hasHTML { return .html }
            if hasRichText { return .richText }
            return .generic
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isColor(trimmed) { return .color }
        if Self.isURL(trimmed) { return .url }
        if Self.isEmail(trimmed) { return .email }
        if Self.isPhone(trimmed) { return .phoneNumber }
        if Self.isJSON(trimmed) { return .json }
        if Self.isShellCommand(trimmed) { return .shellCommand }
        if Self.looksLikeCode(trimmed) { return .code }
        if hasHTML { return .html }
        if hasRichText { return .richText }
        if trimmed.contains("\n\n") { return .multipleParagraphs }
        return .plainText
    }

    private func canonicalData(
        text: String?,
        fileURLs: [URL],
        richText: Data?,
        html: Data?,
        image: Data?,
        pdf: Data?,
        allRepresentations: [PasteboardRepresentation]
    ) -> Data {
        if !fileURLs.isEmpty {
            return Data(fileURLs.map { $0.standardizedFileURL.path }.sorted().joined(separator: "\u{0}").utf8)
        }
        if let image { return image }
        if let pdf { return pdf }
        if let html { return html }
        if let richText { return richText }
        if let text { return Data(text.utf8) }
        return allRepresentations.sorted { $0.typeIdentifier < $1.typeIdentifier }
            .reduce(into: Data()) { result, representation in
                result.append(Data(representation.typeIdentifier.utf8))
                result.append(0)
                result.append(representation.data)
            }
    }

    private func cardStyle(for type: ClipType) -> ClipboardCardStyle {
        switch type {
        case .color: .blue
        case .url: .teal
        default: .dark
        }
    }

    private static func isColor(_ value: String) -> Bool {
        value.range(of: #"^#(?:[0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#, options: .regularExpression) != nil
    }

    private static func isURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "mailto", "ftp"].contains(scheme)
    }

    private static func isEmail(_ value: String) -> Bool {
        value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private static func isPhone(_ value: String) -> Bool {
        value.range(of: #"^\+?[0-9][0-9 ()-]{6,}[0-9]$"#, options: .regularExpression) != nil
    }

    private static func isJSON(_ value: String) -> Bool {
        guard let first = value.first, first == "{" || first == "[", let data = value.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func isShellCommand(_ value: String) -> Bool {
        let first = value.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let commands = ["cd", "ls", "pwd", "git", "swift", "xcodebuild", "npm", "pnpm", "yarn", "brew", "curl", "ssh", "docker"]
        return commands.contains(first) || value.hasPrefix("#!/")
    }

    private static func looksLikeCode(_ value: String) -> Bool {
        let markers = ["func ", "let ", "var ", "class ", "struct ", "import ", "=>", "</", "SELECT ", "def "]
        return markers.contains { value.contains($0) }
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
