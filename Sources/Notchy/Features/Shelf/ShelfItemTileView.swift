import AppKit
import QuickLookUI
import SwiftUI

/// One tile: thumbnail over a two-line name, an accent outline when selected, and a white
/// x in the corner while hovered. An AppKit layer on top handles clicks, keys and drags.
struct ShelfItemTileView: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    let hub: ShelfInteractionHub

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    private var isSelected: Bool { store.isSelected(item.id) }

    var body: some View {
        ZStack {
            VStack(alignment: .center, spacing: 1.5) {
                Image(nsImage: thumbnail ?? ShelfThumbnailCache.symbolCard(systemName: item.kind.symbolName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: ShelfTileMetrics.iconSize, height: ShelfTileMetrics.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: ShelfTileMetrics.cornerRadius))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                Text(item.displayName)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(height: ShelfTileMetrics.labelHeight, alignment: .top)
            }
            .frame(width: ShelfTileMetrics.width)
            .padding(.vertical, ShelfTileMetrics.verticalPadding)
            .padding(.horizontal, ShelfTileMetrics.horizontalPadding)
            .background(background)
            .contentShape(Rectangle())

            ShelfTileInteraction(
                item: item,
                hub: hub,
                isHovering: isHovering,
                onHoverChange: { hovering in
                    withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
                }
            )
        }
        .overlay(alignment: .topTrailing) {
            if isHovering { removeButton }
        }
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .task(id: item.cachedPath ?? item.id.uuidString) { await loadThumbnail() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName.isEmpty ? "Shelf item" : item.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Remove from Shelf") { hub.remove([item]) }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: ShelfTileMetrics.cornerRadius, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: ShelfTileMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: isSelected ? 2 : 1)
            )
    }

    private var removeButton: some View {
        Button {
            hub.remove([item])
        } label: {
            Circle()
                .fill(.white)
                .frame(width: ShelfTileMetrics.removeButtonSize, height: ShelfTileMetrics.removeButtonSize)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 5.5, weight: .bold))
                        .foregroundStyle(.black)
                )
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(ShelfTileMetrics.removeButtonInset)
        .help("Remove from Shelf")
        .accessibilityLabel("Remove from Shelf")
        .transition(.scale.combined(with: .opacity))
    }

    private func loadThumbnail() async {
        switch item.kind {
        case .file:
            guard let url = item.fileURL else { return }
            thumbnail = await ShelfThumbnailCache.shared.thumbnail(for: url)
        case .text, .link:
            thumbnail = ShelfThumbnailCache.symbolCard(systemName: item.kind.symbolName)
        }
    }
}

/// Bridges the tile's AppKit event layer into SwiftUI.
private struct ShelfTileInteraction: NSViewRepresentable {
    let item: ShelfItem
    let hub: ShelfInteractionHub
    let isHovering: Bool
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShelfTileInteractionView {
        let view = ShelfTileInteractionView(item: item)
        configure(view)
        return view
    }

    func updateNSView(_ view: ShelfTileInteractionView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ShelfTileInteractionView) {
        view.item = item
        view.hub = hub
        view.isHovering = isHovering
        view.onHoverChange = onHoverChange
    }
}

/// Sits over a tile. Tracks hover, turns presses into selection clicks or an AppKit drag
/// session (so the copy/move mask can be controlled), answers keys while first responder,
/// and lends the Quick Look panel its item list through the responder chain.
final class ShelfTileInteractionView: NSView, NSDraggingSource {
    var item: ShelfItem
    weak var hub: ShelfInteractionHub?
    var isHovering = false
    var onHoverChange: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var dragStarted = false
    private var draggedItems: [ShelfItem] = []

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    /// The island is a non-activating panel; a click on a tile has to make it key so Space,
    /// arrows and Delete arrive here. The host hands focus back when the island closes.
    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    /// While hovered, the top-trailing corner belongs to the SwiftUI remove button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHovering {
            let local = convert(point, from: superview)
            let corner = NSRect(
                x: bounds.maxX - ShelfTileMetrics.removeHitRegion,
                y: bounds.maxY - ShelfTileMetrics.removeHitRegion,
                width: ShelfTileMetrics.removeHitRegion,
                height: ShelfTileMetrics.removeHitRegion
            )
            if corner.contains(local) { return nil }
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragStarted = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, !dragStarted else { return }
        let travel = hypot(
            event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
            event.locationInWindow.y - mouseDownEvent.locationInWindow.y
        )
        guard travel > ShelfTileMetrics.dragThreshold else { return }
        dragStarted = true
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            dragStarted = false
        }
        guard let mouseDownEvent, !dragStarted else { return }
        let flags = mouseDownEvent.modifierFlags
        if flags.intersection(.deviceIndependentFlagsMask).contains(.control) {
            hub?.showContextMenu(for: item, event: mouseDownEvent, in: self)
            return
        }
        hub?.click(item, modifiers: flags, clickCount: event.clickCount)
    }

    override func rightMouseDown(with event: NSEvent) {
        hub?.showContextMenu(for: item, event: event, in: self)
    }

    override func keyDown(with event: NSEvent) {
        if let command = ShelfKeyCommand(event: event), hub?.handle(command) == true {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Quick Look responder chain

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    // Quick Look calls these on the main thread, but the category they override is not
    // actor-annotated, so the hop has to be stated.
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated { ShelfQuickLookController.shared.attach(to: panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated { ShelfQuickLookController.shared.detach(from: panel) }
    }

    // MARK: Drag session

    private func startDrag(with event: NSEvent) {
        guard let hub else { return }
        let payloads = hub.dragPayloads(for: item)
        guard !payloads.isEmpty else { return }
        draggedItems = payloads.map(\.item)
        let draggingItems = payloads.enumerated().map { index, payload -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: payload.writer)
            let size = payload.image.size
            let stackOffset = CGFloat(index) * 6
            draggingItem.setDraggingFrame(
                NSRect(
                    x: bounds.midX - size.width / 2 + stackOffset,
                    y: bounds.midY - size.height / 2 - stackOffset,
                    width: size.width,
                    height: size.height
                ),
                contents: payload.image
            )
            return draggingItem
        }
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            // Copy unless the user opted into moves: Finder moves by default on the same
            // volume, which would silently relocate the original.
            return hub?.allowsMoveOnDragOut == true ? [.copy, .move] : [.copy]
        case .withinApplication:
            return [.copy]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        hub?.dragWillBegin()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let items = draggedItems
        draggedItems = []
        hub?.dragEnded(operation, items: items)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }
}
