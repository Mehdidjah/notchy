import SwiftUI

/// Lays a tab out at its design size and draws it at `NotchTab.contentScale`, so a compact island
/// shows the same widgets in the same proportions, only smaller. Text and shapes stay vector, so
/// they render sharp at the smaller size; hit testing and gestures follow the transform.
///
/// Only for pure SwiftUI content: AppKit views embedded in a tab (Shelf's tiles, the Notes
/// editor, camera previews) don't follow a SwiftUI scale, so those tabs size themselves instead.
struct IslandScaledContent: ViewModifier {
    var scale: CGFloat = NotchTab.contentScale

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

extension View {
    func islandScaled(_ scale: CGFloat = NotchTab.contentScale) -> some View {
        modifier(IslandScaledContent(scale: scale))
    }
}

/// Design sizes for tabs that can't be drawn through `IslandScaledContent` (they embed AppKit
/// views): `13.island` is 13 design points at the content scale.
extension Int {
    var island: CGFloat { CGFloat(self) * NotchTab.contentScale }
}

extension Double {
    var island: CGFloat { CGFloat(self) * NotchTab.contentScale }
}
