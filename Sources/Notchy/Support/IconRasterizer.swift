import AppKit

/// Draws an image once into a small bitmap. Application icons from the workspace are layered
/// vector images; shown as they are, a redraw of a view that contains one can render the icon
/// again on the CPU in the middle of an animation.
enum IconRasterizer {
    /// `image` drawn into a `pixelSide`-pixel square bitmap, sized at half that in points so
    /// it stays sharp on a 2x display. Nil when no bitmap context can be made.
    static func rasterized(_ image: NSImage, pixelSide: Int) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelSide, pixelsHigh: pixelSide, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSide, height: pixelSide))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: pixelSide / 2, height: pixelSide / 2))
        result.addRepresentation(bitmap)
        return result
    }
}
