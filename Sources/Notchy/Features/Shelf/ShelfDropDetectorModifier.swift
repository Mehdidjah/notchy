import AppKit
import SwiftUI

/// Makes the collapsed notch a drop target. While a drag hovers it, `onTargetChange(true)` is
/// reported so the host can open the island on the Shelf tab; when the drag leaves or ends,
/// `onTargetChange(false)` follows. A drop that lands before the island opened still goes
/// onto the shelf.
struct ShelfDropDetectorModifier: ViewModifier {
    var isEnabled = true
    /// The shelf a drop goes onto; nil means `ShelfStore.shared`, looked up only when a drop
    /// lands, so drawing the closed island never loads the shelf.
    var store: ShelfStore?
    let onTargetChange: (Bool) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrop(of: ShelfDropImporter.acceptedTypes, isTargeted: $isTargeted) { providers in
                    (store ?? .shared).importProviders(providers)
                    return true
                }
                .onChange(of: isTargeted) { _, targeted in
                    onTargetChange(targeted)
                }
        } else {
            content
        }
    }
}

extension View {
    /// See `ShelfDropDetectorModifier`.
    func shelfDropDetector(
        isEnabled: Bool = true,
        store: ShelfStore? = nil,
        onTargetChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(ShelfDropDetectorModifier(isEnabled: isEnabled, store: store, onTargetChange: onTargetChange))
    }
}
