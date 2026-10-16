import AppKit
import SwiftUI

/// Sizes of a shelf tile: 105 wide, a 56-pt thumbnail, a two-line label.
enum ShelfTileMetrics {
    static let width: CGFloat = 105
    static let iconSize: CGFloat = 56
    static let labelHeight: CGFloat = 30
    static let verticalPadding: CGFloat = 10
    static let horizontalPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 12
    static let spacing: CGFloat = 8
    static let removeButtonSize: CGFloat = 20
    static let removeButtonInset: CGFloat = 2
    /// Top-trailing square the drag layer gives up to the remove button while hovering.
    static let removeHitRegion: CGFloat = 30
    /// Pointer travel before a press turns into a drag.
    static let dragThreshold: CGFloat = 4
}

/// Keys the shelf answers while one of its tiles is first responder.
enum ShelfKeyCommand {
    case quickLook
    case open
    case remove
    case moveLeft
    case moveRight
    case selectAll
    case escape

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
            self = .selectAll
            return
        }
        switch event.keyCode {
        case 49: self = .quickLook
        case 36, 76: self = .open
        case 51, 117: self = .remove
        case 123: self = .moveLeft
        case 124: self = .moveRight
        case 53: self = .escape
        default: return nil
        }
    }
}

/// One item on an outgoing drag: what it writes and the picture under the pointer.
struct ShelfDragPayload {
    let item: ShelfItem
    let writer: NSPasteboardWriting
    let image: NSImage
}

/// The picture under the pointer while a tile is dragged out: its thumbnail over the name
/// on an accent-coloured label.
struct ShelfDragPreview: View {
    let thumbnail: NSImage
    let displayName: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ShelfTileMetrics.iconSize, height: ShelfTileMetrics.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: ShelfTileMetrics.cornerRadius))
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
        }
        .frame(width: ShelfTileMetrics.width)
    }
}

/// Keeps hold of an AppKit view inside the SwiftUI tree so pickers and menus have something
/// to anchor to. Not published: finding the view must not redraw anything.
@MainActor
final class ShelfViewAnchor: ObservableObject {
    weak var view: NSView?
}

struct ShelfAnchorView: NSViewRepresentable {
    let anchor: ShelfViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
