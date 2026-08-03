import SwiftUI

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list
    case board

    var id: Self { self }
    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        case .board: "rectangle.split.3x1"
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: NotchViewModel
    @State private var query = ""
    @State private var category: ClipboardCategory = .history
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortNewestFirst = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
        } content: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
            .navigationSplitViewColumnWidth(min: 440, ideal: 620)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("Clipboard Library")
    }

    private var sidebar: some View {
        List(selection: $category) {
            Section("Library") {
                ForEach(ClipboardCategory.allCases) { item in
                    Label {
                        HStack {
                            Text(item.rawValue)
                            Spacer()
                            Text(model.count(for: item).formatted())
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: symbol(for: item))
                    }
                    .tag(item)
                }
            }

            Section("Collections") {
                Label("Unsorted", systemImage: "tray")
                Label("New Collection", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: category) { _, value in model.selectCategory(value) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search text, OCR, files, apps, notes…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: 340, minHeight: 30)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            Picker("View", selection: $viewMode) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)

            Button {
                sortNewestFirst.toggle()
            } label: {
                Label(sortNewestFirst ? "Newest" : "Oldest", systemImage: "arrow.up.arrow.down")
            }

            Spacer()

            Button("Select", systemImage: "checkmark.circle") { model.beginSelection() }
            Button("Settings", systemImage: "gearshape") { model.requestSettings() }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        if visibleItems.isEmpty {
            ContentUnavailableView(
                model.items.isEmpty ? "Your Library is empty" : "No matching clips",
                systemImage: "square.grid.2x2",
                description: Text("Copied content appears here automatically and stays local.")
            )
        } else {
            switch viewMode {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: 12)], spacing: 12) {
                        ForEach(visibleItems) { clip in
                            libraryCard(clip)
                        }
                    }
                    .padding(14)
                }
            case .list:
                List(visibleItems, selection: selectedBinding) { clip in
                    LibraryClipRow(clip: clip)
                        .tag(clip.id)
                        .contextMenu { clipMenu(clip) }
                }
            case .board:
                BoardLibraryView(items: visibleItems, selection: selectedBinding)
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let clip = model.selectedClip {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(clip.contentType.displayName, systemImage: clip.symbolName)
                        .font(.headline)
                    Text(clip.value)
                        .font(clip.kind == .code ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                    inspectorRow("Source", value: clip.sourceApplicationName ?? "Unknown")
                    inspectorRow("Copied", value: clip.lastCopiedAt.formatted())
                    inspectorRow("Copies", value: clip.copyCount.formatted())
                    inspectorRow("Pastes", value: clip.pasteCount.formatted())
                    inspectorRow("Size", value: ByteCountFormatter.string(fromByteCount: clip.byteSize, countStyle: .file))

                    HStack {
                        Button("Copy") { model.copyUsingCoordinator(clip) }
                        Button("Paste") { model.paste(clip) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(clip.isFavorite ? "Remove Favorite" : "Add Favorite") {
                        model.toggleFavorite(clip)
                    }
                    Button("Delete", role: .destructive) { model.delete(clip) }
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Select a clip", systemImage: "sidebar.right")
        }
    }

    private var visibleItems: [Clip] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = model.filteredItems.filter { clip in
            query.isEmpty || [clip.title, clip.searchableText, clip.ocrText, clip.sourceApplicationName, clip.note]
                .compactMap { $0 }
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(query)
        }
        return source.sorted {
            sortNewestFirst ? $0.lastCopiedAt > $1.lastCopiedAt : $0.lastCopiedAt < $1.lastCopiedAt
        }
    }

    private var selectedBinding: Binding<Clip.ID?> {
        Binding(
            get: { model.selectedClip?.id },
            set: { id in
                guard let id, let clip = model.items.first(where: { $0.id == id }) else { return }
                model.setSelectedClip(clip)
            }
        )
    }

    private func libraryCard(_ clip: Clip) -> some View {
        ClipboardCardView(
            item: clip,
            isCopied: model.copiedItemID == clip.id,
            isSelected: model.selectedClipIDs.contains(clip.id),
            width: 154,
            recentShortcut: nil,
            action: { model.setSelectedClip(clip) },
            previewAction: { model.openPreview(clip) },
            favoriteAction: { model.toggleFavorite(clip) },
            pinAction: { model.togglePinned(clip) },
            deleteAction: { model.delete(clip) }
        )
    }

    @ViewBuilder
    private func clipMenu(_ clip: Clip) -> some View {
        Button("Paste") { model.paste(clip) }
        Button("Copy") { model.copyUsingCoordinator(clip) }
        Button("Favorite") { model.toggleFavorite(clip) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(clip) }
    }

    private func inspectorRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func symbol(for category: ClipboardCategory) -> String {
        switch category {
        case .history: "clock.arrow.circlepath"
        case .all: "square.stack.3d.up"
        case .favorites: "star"
        case .pinned: "pin"
        case .text: "doc.text"
        case .images: "photo"
        case .files: "folder"
        case .links: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .colors: "paintpalette"
        case .screenshots: "camera.viewfinder"
        }
    }
}

private struct LibraryClipRow: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: clip.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title).lineLimit(2)
                Text("\(clip.sourceApplicationName ?? "Clipboard") · \(clip.contentType.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(clip.lastCopiedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct BoardLibraryView: View {
    let items: [Clip]
    @Binding var selection: Clip.ID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                boardColumn("Text", types: [.plainText, .multipleParagraphs, .richText, .code, .json])
                boardColumn("Media", types: [.image, .screenshot, .gif, .video, .color])
                boardColumn("Files & Links", types: [.file, .folder, .multipleFiles, .pdf, .url])
            }
            .padding(14)
        }
    }

    private func boardColumn(_ title: String, types: Set<ClipType>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(items.filter { types.contains($0.contentType) }) { clip in
                        Button { selection = clip.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(clip.title).lineLimit(3)
                                Text(clip.sourceApplicationName ?? "Clipboard")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .draggable(clip.id.uuidString)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
