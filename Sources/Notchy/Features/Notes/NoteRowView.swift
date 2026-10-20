import AppKit
import SwiftUI

/// One note in the list: a colour bar, the title and a preview of the body. Hovering swaps
/// the time label for a pill of pin, copy and delete buttons. Compact rows (two-column grid)
/// are smaller in every dimension.
struct NoteRowView: View {
    let note: NoteItem
    let image: NSImage?
    let isCompact: Bool
    let pinningEnabled: Bool
    let onTogglePin: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showsCopied = false
    @State private var copiedResetTask: Task<Void, Never>?

    private static let hoverAnimation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            RoundedRectangle(cornerRadius: 3.island)
                .fill(note.color)
                .frame(width: isCompact ? 3 : 4)
                .padding(.vertical, isCompact ? 4 : 2)

            VStack(alignment: .leading, spacing: isCompact ? 1 : 4) {
                HStack(spacing: 4.island) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: isCompact ? 7 : 8))
                            .foregroundStyle(note.color)
                    }
                    Text(note.title)
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(note.previewText)
                    .font(.system(size: isCompact ? 10 : 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(isCompact ? 1 : 2)
                    .multilineTextAlignment(.leading)
            }
            .animation(Self.hoverAnimation, value: isHovered)

            Spacer(minLength: 0)
        }
        // Room on the right for the hover pill, time label and thumbnail.
        .padding(.trailing, isCompact ? 50 : 130)
        .padding(isCompact ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12.island)
                .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12.island)
                        .stroke(note.color.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12.island))
        .overlay(alignment: .trailing) { trailingAccessories }
        .onHover { hovering in
            withAnimation(Self.hoverAnimation) { isHovered = hovering }
        }
        .onDisappear { copiedResetTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(note.title), \(note.previewText)")
    }

    private var trailingAccessories: some View {
        HStack(spacing: 8.island) {
            if isHovered {
                actionPill
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else if !isCompact {
                Text(NoteOrdering.timeAgo(from: note.creationDate))
                    .font(.system(size: 10.island))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: isCompact ? 32 : 50, height: isCompact ? 32 : 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6.island))
                    .overlay(RoundedRectangle(cornerRadius: 6.island).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .padding(.trailing, isCompact ? 4 : 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.trailing, isCompact ? 2 : 4)
    }

    private var actionPill: some View {
        HStack(spacing: isCompact ? 3 : 4) {
            if pinningEnabled {
                pillButton(
                    note.isPinned ? "pin.slash.fill" : "pin.fill",
                    tint: .white,
                    label: note.isPinned ? "Unpin Note" : "Pin Note",
                    action: onTogglePin
                )
            }
            pillButton(
                showsCopied ? "checkmark" : "doc.on.doc",
                tint: showsCopied ? .green : .white,
                label: "Copy Note",
                action: copy
            )
            pillButton("trash", tint: .red, label: "Delete Note", action: onDelete)
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 3)
        .background(
            Capsule()
                .fill(Color(white: 0.12))
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 3)
        )
        .padding(.vertical, 4.island)
    }

    private func pillButton(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: isCompact ? 9 : 11))
                .foregroundStyle(tint)
                .padding(isCompact ? 5 : 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func copy() {
        onCopy()
        withAnimation { showsCopied = true }
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { showsCopied = false }
        }
    }
}
