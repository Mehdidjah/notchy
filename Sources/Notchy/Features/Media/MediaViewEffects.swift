import AppKit
import SwiftUI

/// Tilts the view towards the pointer while hovering, like a card under a finger: the
/// vertical position rotates about X, the horizontal about Y (inverted), `intensity`
/// degrees at the edges, with a 2 % lift. Springs quickly while moving and settles on exit.
private struct MediaParallaxModifier: ViewModifier {
    let intensity: Double

    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        if intensity <= 0 {
            content
        } else {
            content
                .contentShape(Rectangle())
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { size = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in size = newSize }
                })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard size.width > 0, size.height > 0, NSEvent.pressedMouseButtons == 0 else { return }
                        let x = (location.x / size.width) * 2 - 1
                        let y = (location.y / size.height) * 2 - 1
                        withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.5)) {
                            offset = CGSize(width: x, height: y)
                            isHovering = true
                        }
                    case .ended:
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            offset = .zero
                            isHovering = false
                        }
                    }
                }
                .rotation3DEffect(.degrees(offset.height * intensity), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(offset.width * -intensity), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(isHovering ? 1.02 : 1)
        }
    }
}

/// Turns the artwork about its vertical axis by `angle`, counter-mirroring the back face so
/// the image never reads reversed.
private struct MediaArtworkFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            .scaleEffect(x: Self.faceSign(for: angle), y: 1)
    }

    /// +1 while the front face shows, -1 for the back face.
    static func faceSign(for degrees: Double) -> CGFloat {
        let cosine = cos(degrees * .pi / 180)
        if cosine > 0.001 { return 1 }
        if cosine < -0.001 { return -1 }
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func mediaParallax(intensity: Double) -> some View {
        modifier(MediaParallaxModifier(intensity: intensity))
    }

    func mediaArtworkFlip(angle: Double) -> some View {
        modifier(MediaArtworkFlipModifier(angle: angle))
    }
}

/// The source application's icon, for the badge on the open artwork.
struct MediaAppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if let icon = MediaAppIconCache.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
        }
    }
}

/// Application icons rasterised once per bundle identifier, so redraws of the player do not
/// go back to the workspace for a multi-resolution icon each time.
@MainActor
enum MediaAppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static let pixelSide = 128

    static func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = icons[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        guard let image = IconRasterizer.rasterized(source, pixelSide: pixelSide) else { return source }
        icons[bundleIdentifier] = image
        return image
    }
}
