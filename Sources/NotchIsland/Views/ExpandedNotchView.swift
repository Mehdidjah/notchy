import AppKit
import SwiftUI

struct ExpandedNotchView: View {
    @ObservedObject var model: NotchViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            categoryBar
            historyContent

            if model.state == .multiSelecting {
                MultiPasteTrayView(model: model)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if model.state == .previewing, let clip = model.previewedClip {
                ClipPreviewView(
                    clip: clip,
                    copyAction: { model.copyUsingCoordinator(clip) },
                    pasteAction: { model.paste(clip) },
                    favoriteAction: { model.toggleFavorite(clip) },
                    closeAction: model.closePreview
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .foregroundStyle(.white)
        .onChange(of: isSearchFocused) { _, focused in
            model.setKeyboardFocus(focused)
        }
        .onKeyPress(.leftArrow) {
            model.selectNext(delta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.selectNext(delta: 1)
            return .handled
        }
        .onKeyPress(.space) {
            if model.state == .previewing {
                model.closePreview()
            } else if let clip = model.selectedClip {
                model.openPreview(clip)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let clip = model.selectedClip { model.paste(clip) }
            return .handled
        }
        .onExitCommand(perform: model.escape)
        .animation(.easeOut(duration: 0.18), value: model.state)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))

                TextField("Search clipboard", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search clipboard history")

                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 300, minHeight: 32)
            .background(Color.white.opacity(0.07), in: Capsule())

            HStack(spacing: 5) {
                Circle()
                    .fill(model.settings.captureEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.settings.captureEnabled ? "Saving" : "Paused")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 18)

            toolbarButton(
                model.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle",
                label: "Select multiple",
                selected: model.isSelectionMode
            ) {
                model.isSelectionMode ? model.endSelection() : model.beginSelection()
            }
            toolbarButton("square.grid.2x2", label: "Open Library") { model.requestLibrary() }
            toolbarButton(
                model.isPinnedOpen ? "pin.fill" : "pin",
                label: model.isPinnedOpen ? "Unpin shelf" : "Pin shelf",
                selected: model.isPinnedOpen,
                action: model.togglePin
            )
            toolbarButton("gearshape", label: "Settings") { model.requestSettings() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .frame(height: 53)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(ClipboardCategory.allCases) { category in
                    CategoryPill(
                        title: category.rawValue,
                        count: model.count(for: category),
                        isSelected: model.selectedCategory == category
                    ) {
                        model.selectCategory(category)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .frame(height: 40)
    }

    @ViewBuilder
    private var historyContent: some View {
        if model.filteredItems.isEmpty {
            ContentUnavailableView(
                model.items.isEmpty ? "Copy something to begin" : "Nothing found",
                systemImage: "doc.on.clipboard",
                description: Text(model.items.isEmpty
                    ? "Your clipboard history stays local on this Mac."
                    : "Try another search or filter.")
            )
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 152, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardCardView(
                                item: item,
                                isCopied: model.copiedItemID == item.id,
                                isSelected: model.selectedClipIDs.contains(item.id),
                                width: model.usesCompactCards ? 126 : 142,
                                recentShortcut: index < 10 ? (index == 9 ? 0 : index + 1) : nil,
                                action: { activate(item) },
                                previewAction: { model.openPreview(item) },
                                favoriteAction: { model.toggleFavorite(item) },
                                pinAction: { model.togglePinned(item) },
                                deleteAction: { model.delete(item) }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .frame(minHeight: 150, maxHeight: 164)
                .onChange(of: model.selectedClipID) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                }
                .onChange(of: model.selectedCategory) { _, _ in
                    if let first = model.filteredItems.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
        }
    }

    private func activate(_ item: Clip) {
        model.setSelectedClip(item)
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            model.selectRange(to: item)
        } else if modifiers.contains(.command) || model.isSelectionMode {
            model.toggleSelection(item)
        } else {
            model.performPrimaryAction(item)
        }
    }

    private func toolbarButton(
        _ symbol: String,
        label: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(0.62))
                .frame(width: 32, height: 32)
                .background(selected ? Color.white : Color.white.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CategoryPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text(count.formatted())
                    .opacity(0.5)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black.opacity(0.78) : .white.opacity(0.58))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(isSelected ? Color.white : Color.white.opacity(0.075), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
