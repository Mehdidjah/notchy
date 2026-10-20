import SwiftUI

/// The notes list: a header with the title and round actions, an optional search and colour
/// filter row, then the notes as one column, or two compact columns once there are more than three.
struct NoteListPane: View {
    @ObservedObject var controller: NotesTabController
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: NotesSettings
    @ObservedObject var sync: AppleNotesSyncManager

    @State private var searchText = ""
    @State private var colorFilter: Int?
    @State private var isSearchExpanded = false
    @State private var isConfirmingDeleteAll = false

    private static let paneSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    private var visibleNotes: [NoteItem] {
        store.notes(matching: searchText, colorIndex: colorFilter)
    }

    var body: some View {
        let notes = visibleNotes
        VStack(spacing: 0) {
            header

            if isSearchExpanded {
                searchAndFilterRow
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 7)
            }

            if notes.isEmpty {
                emptyState
            } else {
                grid(notes)
            }
        }
        .frame(maxHeight: .infinity)
        .alert("Delete All Notes?", isPresented: $isConfirmingDeleteAll) {
            Button("Delete", role: .destructive) { controller.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved note and its attachments.")
        }
        .onChange(of: isConfirmingDeleteAll) { _, showing in
            controller.setIslandHold(showing)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if settings.appleNotesSyncEnabled {
                Image(systemName: sync.isSyncing ? "arrow.triangle.2.circlepath" : "apple.logo")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(sync.isSyncing ? Color.yellow : Color.white.opacity(0.45))
                    .rotationEffect(.degrees(sync.isSyncing ? 360 : 0))
                    .animation(
                        sync.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: sync.isSyncing
                    )
                    .help(sync.lastError ?? "Synced with Apple Notes")
            }

            Spacer()

            if settings.appleNotesSyncEnabled {
                headerButton(
                    "arrow.triangle.2.circlepath",
                    size: 13,
                    tint: sync.isSyncing ? .yellow : .white.opacity(0.6),
                    help: "Sync with Apple Notes"
                ) {
                    sync.requestSync()
                }
                .disabled(sync.isSyncing)
            }

            if settings.showsSearchButton {
                Button {
                    withAnimation(Self.paneSpring) { isSearchExpanded.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: isSearchExpanded ? .bold : .medium))
                        .symbolVariant(isSearchExpanded ? .circle.fill : .none)
                        .frame(width: 11, height: 11)
                        .foregroundStyle(isSearchExpanded ? Color.blue : Color.white.opacity(0.6))
                        .padding(3.5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isSearchExpanded ? "Hide Search" : "Search Notes")
                .accessibilityLabel("Search notes")
            }

            if settings.createFromClipboardEnabled {
                headerButton("doc.on.clipboard", size: 13, tint: .white.opacity(0.6), help: "Create from Clipboard") {
                    controller.createFromClipboard()
                }
            }

            if !store.isEmpty {
                headerButton("trash", size: 14, tint: .red, help: "Delete All Notes") {
                    isConfirmingDeleteAll = true
                }
            }

            headerButton("plus", size: 14, weight: .bold, tint: .white, help: "New Note") {
                controller.createNote()
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 5.5)
        .padding(.bottom, isSearchExpanded ? 4 : 2)
    }

    private func headerButton(
        _ symbol: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .frame(width: 11, height: 11)
                .foregroundStyle(tint)
                .padding(3.5)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Search and colour filter

    private var searchAndFilterRow: some View {
        VStack(spacing: 4) {
            if settings.searchEnabled && !store.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    TextField("Search notes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5.5))
                .padding(.horizontal, 11)
            }

            if settings.colorFilteringEnabled && !store.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button {
                            colorFilter = nil
                        } label: {
                            Text("All")
                                .font(.system(size: 7, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(colorFilter == nil ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        ForEach(NoteItem.palette.indices, id: \.self) { index in
                            Circle()
                                .fill(NoteItem.palette[index])
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: colorFilter == index ? 2 : 0)
                                        .padding(-2)
                                )
                                .contentShape(Circle())
                                .onTapGesture {
                                    withAnimation { colorFilter = colorFilter == index ? nil : index }
                                }
                                .accessibilityElement()
                                .accessibilityLabel("\(NoteItem.paletteNames[index]) notes")
                                .accessibilityAddTraits(colorFilter == index ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, 11)
                }
            }
        }
    }

    // MARK: - Content

    private var emptyState: some View {
        let isSearching = !searchText.isEmpty
        return VStack {
            Spacer()
            HStack(spacing: 5.5) {
                Image(systemName: isSearching ? "magnifyingglass" : "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text(isSearching ? "No results found" : "No notes yet")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(.top, 7)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(_ notes: [NoteItem]) -> some View {
        let isCompact = notes.count > 3
        let columns = isCompact
            ? [GridItem(.flexible(), spacing: 5.5), GridItem(.flexible(), spacing: 5.5)]
            : [GridItem(.flexible())]
        return ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 5.5) {
                    ForEach(notes) { note in
                        NoteRowView(
                            note: note,
                            image: store.image(for: note),
                            isCompact: isCompact,
                            pinningEnabled: settings.pinningEnabled,
                            onTogglePin: { controller.togglePin(note) },
                            onCopy: { controller.copy(note) },
                            onDelete: { controller.delete(note) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { controller.open(note) }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 14)
            }

            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 11)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .frame(height: 11)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
    }
}
