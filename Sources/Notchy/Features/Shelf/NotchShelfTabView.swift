import AppKit
import SwiftUI

/// Shelf tab content: a square share target on the left and, beside it, a dashed drop panel
/// holding a scrolling row of tiles for everything dropped on the island. Content box is
/// 612 x 168 pt inside the open island.
struct NotchShelfTabView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var store: ShelfStore
    @ObservedObject private var settings: ShelfSettings
    @StateObject private var hub: ShelfInteractionHub
    @StateObject private var panelAnchor = ShelfViewAnchor()
    @State private var isPanelTargeted = false

    init(model: NotchViewModel, store: ShelfStore = .shared, settings: ShelfSettings = .shared) {
        _model = ObservedObject(wrappedValue: model)
        _store = ObservedObject(wrappedValue: store)
        _settings = ObservedObject(wrappedValue: settings)
        _hub = StateObject(wrappedValue: ShelfInteractionHub(store: store, settings: settings))
    }

    var body: some View {
        HStack(spacing: 12) {
            ShelfShareDropZone(store: store, settings: settings, hub: hub)
            shelfPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: wireHub)
        .task { await store.pruneMissingFiles() }
        .onChange(of: store.selectedIDs) { _, _ in
            hub.refreshQuickLookIfPresented()
        }
    }

    // MARK: Panel

    private var shelfPanel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                isPanelTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay { panelContent.padding(16) }
            .overlay(alignment: .topTrailing) {
                if !store.isEmpty {
                    toolbar.padding(6)
                }
            }
            .background(ShelfAnchorView(anchor: panelAnchor))
            .contentShape(Rectangle())
            .onTapGesture { store.clearSelection() }
            .onDrop(of: ShelfDropImporter.acceptedTypes, isTargeted: $isPanelTargeted) { providers in
                // A tile dragged within the island is not a new drop.
                guard !store.isDraggingOut else { return false }
                store.importProviders(providers)
                return true
            }
            .animation(.easeInOut(duration: 0.15), value: isPanelTargeted)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Shelf")
    }

    @ViewBuilder
    private var panelContent: some View {
        if store.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, .gray)
                    .imageScale(.large)
                Text(store.isImporting ? "Adding…" : "Drop files here")
                    .foregroundStyle(.gray)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: ShelfTileMetrics.spacing) {
                    ForEach(store.items) { item in
                        ShelfItemTileView(item: item, store: store, hub: hub)
                    }
                }
            }
            // The viewport reaches 8 pt into the padding so a half-scrolled tile fades at the
            // edge instead of being cut at the dashed line.
            .padding(-ShelfTileMetrics.spacing)
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(
                "square.and.arrow.up",
                help: store.hasSelection ? "Share selected items" : "Share all items"
            ) {
                hub.share(store.hasSelection ? store.selectedItems : store.items, from: panelAnchor.view)
            }
            toolbarButton("trash", tint: .red, help: "Clear shelf") {
                hub.clear()
            }
        }
    }

    private func toolbarButton(
        _ symbol: String,
        tint: Color = .white,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Host wiring

    /// Drags and share sheets take the pointer off the island; the view model's drag hold
    /// keeps it open until they finish.
    private func wireHub() {
        hub.holdOpen = { [weak model] in model?.holdOpen(reason: "shelf") }
        hub.releaseHold = { [weak model] in model?.releaseHold(reason: "shelf") }
        hub.sharing.onBegin = { [weak hub] in hub?.holdOpen?() }
        hub.sharing.onEnd = { [weak hub] in hub?.releaseHold?() }
    }
}
