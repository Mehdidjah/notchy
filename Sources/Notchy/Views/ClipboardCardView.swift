import SwiftUI

struct ClipboardCardView: View {
    let item: Clip
    let isCopied: Bool
    let isSelected: Bool
    let width: CGFloat
    let recentShortcut: Int?
    let action: () -> Void
    let previewAction: () -> Void
    let favoriteAction: () -> Void
    let pinAction: () -> Void
    let deleteAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                cardContent

                if isCopied {
                    statusBadge("Copied", symbol: "checkmark")
                } else if isSelected {
                    statusBadge("Selected", symbol: "checkmark")
                } else if let recentShortcut {
                    Text("⌃⌘\(recentShortcut)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .foregroundStyle(foregroundColor.opacity(0.8))
                        .background(foregroundColor.opacity(0.12), in: Capsule())
                        .padding(9)
                } else if item.isPinned || item.isFavorite {
                    Image(systemName: item.isPinned ? "pin.fill" : "star.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(foregroundColor.opacity(0.7))
                        .padding(11)
                }

                if isHovered && !isSelected {
                    hoverActions
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: width, height: 126)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.85) : borderColor,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .scaleEffect(isHovered ? 1.015 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.28 : 0.12), radius: isHovered ? 12 : 5, y: 4)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Paste", systemImage: "arrow.down.doc") { action() }
            Button("Preview", systemImage: "eye") { previewAction() }
            Button(item.isFavorite ? "Remove Favorite" : "Favorite", systemImage: "star") {
                favoriteAction()
            }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: "pin") { pinAction() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleteAction() }
        }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.snappy(duration: 0.2, extraBounce: 0), value: isCopied)
        .animation(.snappy(duration: 0.2, extraBounce: 0), value: isSelected)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityValue(isSelected ? "Selected" : item.contentType.displayName)
        .accessibilityHint("Activates the configured clipboard action")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.contentType.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor.opacity(0.62))

            Spacer(minLength: 7)

            Text(item.title)
                .font(item.kind == .code
                    ? .system(size: 12, weight: .medium, design: .monospaced)
                    : .system(size: item.kind == .color ? 18 : 13, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(item.kind == .color ? 2 : 4)
                .truncationMode(.tail)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 7)

            HStack(spacing: 5) {
                Text(item.sourceApplicationName ?? "Clipboard")
                    .lineLimit(1)
                Text("·")
                Text(item.lastCopiedAt, style: .relative)
                    .lineLimit(1)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(foregroundColor.opacity(0.55))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            miniButton("eye", label: "Preview", action: previewAction)
            miniButton(item.isFavorite ? "star.fill" : "star", label: "Favorite", action: favoriteAction)
            miniButton("pin", label: "Pin", action: pinAction)
        }
        .padding(5)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func miniButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func statusBadge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 23, height: 23)
            .foregroundStyle(.black)
            .background(.white, in: Circle())
            .padding(8)
    }

    private var backgroundColor: Color {
        if item.contentType == .color,
           let color = Color(hex: item.detectedColors.first ?? item.plainText ?? "") {
            return color
        }
        return switch item.style {
        case .light: Color(white: 0.93)
        case .dark: Color(red: 0.095, green: 0.095, blue: 0.105)
        case .blue: Color(red: 0, green: 0.50, blue: 1)
        case .teal: Color(red: 0.02, green: 0.30, blue: 0.28)
        }
    }

    private var foregroundColor: Color {
        item.style == .light ? .black : .white
    }

    private var borderColor: Color {
        item.style == .light ? .black.opacity(0.07) : .white.opacity(0.10)
    }
}

private extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
