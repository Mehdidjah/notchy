import SwiftUI

struct QuickPasteView: View {
    @ObservedObject var model: NotchViewModel
    let close: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($searchFocused)
                Text("⌃⌘V")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.quaternary.opacity(0.7), in: Capsule())
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Divider()

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    model.items.isEmpty ? "Clipboard history is empty" : "No matching clips",
                    systemImage: "doc.on.clipboard",
                    description: Text(model.items.isEmpty ? "Copy something in any app to save it here." : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, clip in
                                quickRow(clip, index: index)
                                    .id(clip.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard filteredItems.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(filteredItems[index].id, anchor: .center)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Preview", systemImage: "space")
                Label("Paste", systemImage: "return")
                Spacer()
                Text("Esc to close")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 500)
        .background(.ultraThickMaterial)
        .task { searchFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(max(0, filteredItems.count - 1), selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            activateSelected()
            return .handled
        }
        .onKeyPress(.space) {
            if filteredItems.indices.contains(selectedIndex) {
                model.openPreview(filteredItems[selectedIndex])
            }
            return .handled
        }
        .onExitCommand(perform: close)
    }

    private var filteredItems: [Clip] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return model.items }
        return model.items.filter {
            [$0.title, $0.searchableText, $0.ocrText, $0.sourceApplicationName, $0.note]
                .compactMap { $0 }
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(value)
        }
    }

    private func quickRow(_ clip: Clip, index: Int) -> some View {
        Button {
            selectedIndex = index
            model.paste(clip)
            close()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: clip.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(index == selectedIndex ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(clip.sourceApplicationName ?? "Clipboard")
                        Text("·")
                        Text(clip.lastCopiedAt, style: .relative)
                        Text("·")
                        Text(clip.contentType.displayName)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if index < 10 {
                    Text("⌃⌘\(index == 9 ? 0 : index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private func activateSelected() {
        guard filteredItems.indices.contains(selectedIndex) else { return }
        model.paste(filteredItems[selectedIndex])
        close()
    }
}
