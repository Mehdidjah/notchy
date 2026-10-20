import SwiftUI

/// Claude Code's mark: the small pixel creature with two eyes and four legs, drawn as a vector
/// from its 24 × 24 artwork. The figure fills x 0…24, y 5…20 of that artwork; the shape fits
/// that box into its frame without stretching, centred.
struct ClaudeCodeLogoShape: Shape {
    /// The figure's outline in artwork coordinates: head and arms, then legs along the bottom.
    private static let body: [CGPoint] = [
        (20.998, 10.949), (24, 10.949), (24, 14.051), (21, 14.051), (21, 17.079),
        (19.513, 17.079), (19.513, 20), (18, 20), (18, 17.079), (16.513, 17.079),
        (16.513, 20), (15, 20), (15, 17.079), (9, 17.079), (9, 20), (7.488, 20),
        (7.488, 17.079), (6, 17.079), (6, 20), (4.487, 20), (4.487, 17.079), (3, 17.079),
        (3, 14.05), (0, 14.05), (0, 10.95), (3, 10.95), (3, 5), (20.998, 5),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// The eyes, cut out of the body.
    private static let eyes: [CGRect] = [
        CGRect(x: 6, y: 8.102, width: 1.488, height: 2.847),
        CGRect(x: 16.51, y: 8.102, width: 1.49, height: 2.847),
    ]

    /// The figure's bounds in artwork coordinates.
    static let artworkBounds = CGRect(x: 0, y: 5, width: 24, height: 15)
    static var aspectRatio: CGFloat { artworkBounds.width / artworkBounds.height }

    func path(in rect: CGRect) -> Path {
        let bounds = Self.artworkBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let origin = CGPoint(
            x: rect.midX - bounds.width * scale / 2 - bounds.minX * scale,
            y: rect.midY - bounds.height * scale / 2 - bounds.minY * scale
        )
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)

        var path = Path()
        path.addLines(Self.body)
        path.closeSubpath()
        for eye in Self.eyes {
            path.addRect(eye)
        }
        return path.applying(transform)
    }
}

/// The mark in Claude's orange. Fill it with the even-odd rule so the eyes stay open.
struct ClaudeCodeLogo: View {
    var color: Color = ClaudeMark.orange

    var body: some View {
        ClaudeCodeLogoShape()
            .fill(color, style: FillStyle(eoFill: true))
            .aspectRatio(ClaudeCodeLogoShape.aspectRatio, contentMode: .fit)
            .accessibilityHidden(true)
    }
}
