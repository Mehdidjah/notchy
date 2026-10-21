// Splits Notchy's artwork into the layers of a Liquid Glass icon, so macOS renders it like its
// own icons: the "Notchy." wordmark and the black band with its notch become glass over the
// gradient.
//
//   swift script/app-icon/make-layers.swift <artwork.png> <output folder>
//
// writes wordmark.png, panel.png and background.png, each on Icon Composer's 1024-pt canvas.
// The band and the notch are measured in the artwork and redrawn as clean shapes; the wordmark
// is white on the band's pure black, so its brightness is its coverage and lifting it out keeps
// every anti-aliased edge; under the band and the notch, the gradient is carried up from the
// first row below them.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-layers.swift <artwork.png> <output folder>\n".utf8))
    exit(2)
}

let size = 1024
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    FileHandle.standardError.write(Data("can't read \(arguments[1])\n".utf8))
    exit(1)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func makeContext(_ side: Int) -> CGContext {
    CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

/// RGBA pixels of a context, row 0 at the top.
struct Pixels {
    let side: Int
    let bytes: UnsafeMutablePointer<UInt8>

    init(_ context: CGContext) {
        side = context.width
        bytes = context.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
    }

    func brightness(_ x: Int, _ y: Int) -> Int {
        let i = (y * side + x) * 4
        return max(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}

// MARK: Measure, at twice the canvas size for sub-point precision

let probeSide = size * 2
let probe = makeContext(probeSide)
probe.interpolationQuality = .high
probe.draw(artwork, in: CGRect(x: 0, y: 0, width: probeSide, height: probeSide))
let measured = Pixels(probe)
let dark = 40

var bandRows = 0
while bandRows < probeSide, measured.brightness(4, bandRows) <= 12 { bandRows += 1 }
guard bandRows > probeSide / 4, bandRows < probeSide * 3 / 4 else { fail("couldn't find the black band (\(bandRows) rows)") }
let notchProbeRow = bandRows + 20
let middle = probeSide / 2
guard measured.brightness(middle, notchProbeRow) <= dark else { fail("no notch under the middle of the band") }
var notchLeft = middle
while notchLeft > 0, measured.brightness(notchLeft - 1, notchProbeRow) <= dark { notchLeft -= 1 }
var notchRight = middle
while notchRight < probeSide - 1, measured.brightness(notchRight + 1, notchProbeRow) <= dark { notchRight += 1 }
var notchBottom = notchProbeRow
while notchBottom < probeSide - 1, measured.brightness(middle, notchBottom + 1) <= dark { notchBottom += 1 }
// The bottom corners start at the first row where the notch's left edge moves in.
func leftEdge(_ row: Int) -> Int {
    var left = middle
    while left > 0, measured.brightness(left - 1, row) <= dark { left -= 1 }
    return left
}
var cornerTop = notchProbeRow
while cornerTop < notchBottom, leftEdge(cornerTop) <= notchLeft { cornerTop += 1 }

// In canvas points.
let scale = CGFloat(size) / CGFloat(probeSide)
let band = (CGFloat(bandRows) + 0.5) * scale
let notch = CGRect(
    x: CGFloat(notchLeft) * scale,
    y: band - 1,
    width: CGFloat(notchRight - notchLeft + 1) * scale,
    height: CGFloat(notchBottom + 1) * scale - (band - 1)
)
let cornerRadius = max(2, min(notch.height / 2, CGFloat(notchBottom + 1 - cornerTop) * scale))

// MARK: Draw

let full = makeContext(size)
full.interpolationQuality = .high
full.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
let art = Pixels(full)

let background = makeContext(size)
let wordmark = makeContext(size)
let back = Pixels(background)
let mark = Pixels(wordmark)
let firstGradientRow = Int(band.rounded(.up)) + 1
let firstRowUnderNotch = Int(notch.maxY.rounded(.up)) + 1
for x in 0..<size {
    let underNotch = CGFloat(x) + 1 >= notch.minX && CGFloat(x) <= notch.maxX
    let firstRow = underNotch ? firstRowUnderNotch : firstGradientRow
    for y in 0..<size {
        let i = (y * size + x) * 4
        let from = (max(y, firstRow) * size + x) * 4
        back.bytes[i] = art.bytes[from]
        back.bytes[i + 1] = art.bytes[from + 1]
        back.bytes[i + 2] = art.bytes[from + 2]
        back.bytes[i + 3] = 255
        if CGFloat(y) < band {
            // Premultiplied white: every channel is the coverage.
            let coverage = UInt8(art.brightness(x, y))
            mark.bytes[i] = coverage
            mark.bytes[i + 1] = coverage
            mark.bytes[i + 2] = coverage
            mark.bytes[i + 3] = coverage
        }
    }
}

// The band and the notch as one black shape, drawn top-down.
let panel = makeContext(size)
panel.translateBy(x: 0, y: CGFloat(size))
panel.scaleBy(x: 1, y: -1)
let shape = CGMutablePath()
shape.addRect(CGRect(x: 0, y: 0, width: CGFloat(size), height: band))
shape.move(to: CGPoint(x: notch.minX, y: notch.minY))
shape.addLine(to: CGPoint(x: notch.maxX, y: notch.minY))
shape.addArc(tangent1End: CGPoint(x: notch.maxX, y: notch.maxY), tangent2End: CGPoint(x: notch.minX, y: notch.maxY), radius: cornerRadius)
shape.addArc(tangent1End: CGPoint(x: notch.minX, y: notch.maxY), tangent2End: CGPoint(x: notch.minX, y: notch.minY), radius: cornerRadius)
shape.closeSubpath()
panel.addPath(shape)
panel.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
panel.fillPath()

func write(_ context: CGContext, _ name: String) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("can't write \(name)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(name)") }
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
write(wordmark, "wordmark.png")
write(panel, "panel.png")
write(background, "background.png")
print(String(format: "band %.1f pt, notch %.1f–%.1f × %.1f–%.1f pt, corners %.1f pt",
             band, notch.minX, notch.maxX, notch.minY, notch.maxY, cornerRadius))
