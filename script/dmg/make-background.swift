// Draws the background of the window the Notchy disk image opens in: the black band with its
// notch from the app icon, the instruction to drag Notchy into Applications, and an arrow
// between the two icons over the icon's blue and orange.
//
//   swift script/dmg/make-background.swift <output.png> <scale> <width> <height> <app x> <applications x> <icons y>
//
// Sizes and positions are in points; `scale` 2 draws the Retina version. Finder writes the icon
// names in black in light mode and in white in dark mode, so the strip under the icons stays a
// mid blue that both read on. The picture runs on below `height`, so a window whose title bar is
// a little shorter than expected never shows Finder's plain background under it.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 8,
      let scale = Double(arguments[2]), let width = Double(arguments[3]), let height = Double(arguments[4]),
      let appX = Double(arguments[5]), let applicationsX = Double(arguments[6]), let iconsY = Double(arguments[7]) else {
    FileHandle.standardError.write(Data("usage: make-background.swift <output.png> <scale> <width> <height> <app x> <applications x> <icons y>\n".utf8))
    exit(2)
}

let overrun = 60.0
let canvas = CGSize(width: width, height: height + overrun)
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale), bitsPerComponent: 8,
          bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { exit(1) }

// Top-down points.
context.scaleBy(x: scale, y: scale)
context.translateBy(x: 0, y: canvas.height)
context.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func glow(_ hex: UInt32, alpha: CGFloat, at center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// MARK: The icon's gradient

let blue = CGGradient(colorsSpace: space, colors: [color(0x3A86C2), color(0x2B70B4), color(0x2A64A6)] as CFArray, locations: [0, 0.55, 1])!
context.drawLinearGradient(blue, start: .zero, end: CGPoint(x: width, y: canvas.height), options: [])
glow(0x1F5C9C, alpha: 0.75, at: CGPoint(x: width * 0.92, y: height * 0.42), radius: 200)
glow(0x4A90D0, alpha: 0.5, at: CGPoint(x: width * 0.08, y: height * 0.5), radius: 170)
glow(0xFF8A14, alpha: 1, at: CGPoint(x: width * 0.5, y: height + 62), radius: 190)
glow(0xFFBE45, alpha: 0.85, at: CGPoint(x: width * 0.2, y: height + 42), radius: 150)
glow(0xF0612A, alpha: 0.7, at: CGPoint(x: width * 0.84, y: height + 48), radius: 140)

// MARK: The band and its notch

let band = 92.0
let notch = CGRect(x: (width - 132) / 2, y: band - 1, width: 132, height: 19)
let shape = CGMutablePath()
shape.addRect(CGRect(x: 0, y: 0, width: width, height: band))
let corner = 7.0
shape.move(to: CGPoint(x: notch.minX, y: notch.minY))
shape.addLine(to: CGPoint(x: notch.maxX, y: notch.minY))
shape.addArc(tangent1End: CGPoint(x: notch.maxX, y: notch.maxY), tangent2End: CGPoint(x: notch.minX, y: notch.maxY), radius: corner)
shape.addArc(tangent1End: CGPoint(x: notch.minX, y: notch.maxY), tangent2End: CGPoint(x: notch.minX, y: notch.minY), radius: corner)
shape.closeSubpath()
context.addPath(shape)
context.setFillColor(color(0x000000))
context.fillPath()

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = string.size()
    string.draw(at: CGPoint(x: (width - size.width) / 2, y: y - size.height / 2))
}

drawCentered("Drag Notchy into Applications", font: .systemFont(ofSize: 22, weight: .bold), color: .white, y: 38)
drawCentered("Then open it from your Applications folder.", font: .systemFont(ofSize: 13, weight: .medium), color: NSColor(white: 1, alpha: 0.62), y: 65)

// MARK: The arrow from the app to Applications

let inset = 74.0
let start = CGPoint(x: appX + inset, y: iconsY)
let end = CGPoint(x: applicationsX - inset, y: iconsY)
let head = 13.0
context.setStrokeColor(color(0xFFFFFF, 0.92))
context.setLineWidth(5)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 6, color: color(0x0B2A4A, 0.35))
let arrow = CGMutablePath()
arrow.move(to: start)
arrow.addLine(to: CGPoint(x: end.x - 2, y: end.y))
arrow.move(to: CGPoint(x: end.x - head, y: end.y - head))
arrow.addLine(to: end)
arrow.addLine(to: CGPoint(x: end.x - head, y: end.y + head))
context.addPath(arrow)
context.strokePath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, "public.png" as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { exit(1) }
