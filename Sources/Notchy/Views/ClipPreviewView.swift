import SwiftUI

struct ClipPreviewView: View {
    let clip: Clip
    let copyAction: () -> Void
    let pasteAction: () -> Void
    let favoriteAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: clip.symbolName)
                    Text(clip.contentType.displayName)
                    Text("·")
                    Text(clip.sourceApplicationName ?? "Clipboard")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

                ScrollView {
                    Text(clip.value.isEmpty ? "No text preview is available." : clip.value)
                        .font(clip.kind == .code
                            ? .system(size: 12, design: .monospaced)
                            : .system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .foregroundStyle(.white.opacity(0.9))
                }

                if let ocrText = clip.ocrText, !ocrText.isEmpty {
                    Text("OCR: \(ocrText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 8) {
                previewButton("Paste", symbol: "arrow.down.doc.fill", primary: true, action: pasteAction)
                previewButton("Copy", symbol: "doc.on.doc", action: copyAction)
                previewButton(
                    clip.isFavorite ? "Unfavorite" : "Favorite",
                    symbol: clip.isFavorite ? "star.fill" : "star",
                    action: favoriteAction
                )
                Spacer()
                previewButton("Close", symbol: "xmark", action: closeAction)
            }
            .frame(width: 112)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview: \(clip.title)")
    }

    private func previewButton(
        _ title: String,
        symbol: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(primary ? .black : .white.opacity(0.75))
                .background(primary ? Color.white : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
