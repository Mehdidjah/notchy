import SwiftUI

/// The clipboard as a card grid inside the island: tap performs the configured action,
/// hover reveals delete, and cards can be dragged straight out into other apps.
struct NotchClipboardTabView: View {
    @ObservedObject var model: NotchViewModel
    @State private var hoveredClipID: Clip.ID?
    @State private var showClearHistoryAlert = false

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: .infinity), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.items) { clip in
                            ClipGridCard(
                                clip: clip,
                                isHovered: hoveredClipID == clip.id,
                                justCopied: model.copiedItemID == clip.id,
                                onDelete: { model.delete(clip) }
                            )
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { hoveredClipID = clip.id }
                                else if hoveredClipID == clip.id { hoveredClipID = nil }
                            }
                            .onTapGesture { model.performPrimaryAction(clip) }
                            .modifier(DragOutModifier(clip: clip, model: model))
                            .contextMenu {
                                Button("Paste", systemImage: "arrow.down.doc") { model.paste(clip) }
                                Button("Copy", systemImage: "doc.on.doc") { model.copyUsingCoordinator(clip) }
                                Button(clip.isFavorite ? "Remove Favorite" : "Favorite", systemImage: "star") {
                                    model.toggleFavorite(clip)
                                }
                                Button(clip.isPinned ? "Unpin" : "Pin", systemImage: "pin") { model.togglePinned(clip) }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(clip) }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(clip.contentType.displayName): \(clip.title)")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Clear History", role: .destructive) { model.clearHistoryPreservingProtected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Favorites and pinned clips are kept.")
        }
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                model.requestLibrary()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open the Clipboard Library")
            HStack(spacing: 5) {
                Circle()
                    .fill(model.settings.captureEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.settings.captureEnabled ? "Saving" : "Paused")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            if !model.items.isEmpty {
                Button {
                    showClearHistoryAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 16, height: 16)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear unprotected history")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No copies yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Copy something to see it here")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }
}

/// Makes a card draggable out of the island when the clip can travel as one item.
private struct DragOutModifier: ViewModifier {
    let clip: Clip
    let model: NotchViewModel

    func body(content: Content) -> some View {
        if clip.isDraggable {
            content.onDrag {
                model.beginDragOut()
                return clip.dragItemProvider()
            }
        } else {
            content
        }
    }
}

/// One clip as a compact card: type tile, one-line preview, type and age underneath,
/// and a hover-revealed delete button in the top-trailing corner.
struct ClipGridCard: View {
    let clip: Clip
    let isHovered: Bool
    let justCopied: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(clip.contentType.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if clip.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                    } else if clip.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(clip.lastCopiedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Delete this clip")
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: justCopied)
    }

    private var tile: some View {
        ZStack {
            if clip.contentType == .color, let color = Color(hexString: clip.detectedColors.first ?? clip.plainText ?? "") {
                RoundedRectangle(cornerRadius: 6).fill(color)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
            }
            Image(systemName: justCopied ? "checkmark.circle.fill" : clip.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(justCopied ? Color.green : Color.blue)
        }
        .frame(width: 28, height: 28)
    }
}

extension Color {
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let rgb = value.count == 8 ? number >> 8 : number
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}
