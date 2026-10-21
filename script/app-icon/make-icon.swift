// Draws Notchy's square artwork into the shape macOS gives app icons: a rounded square with
// continuous corners, 824 pt wide and centred on a transparent 1024-pt canvas, like every
// other app in the Dock and the Finder.
//
//   swift script/app-icon/make-icon.swift <artwork.png> <icon-1024.png>

import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <artwork.png> <icon-1024.png>\n".utf8))
    exit(2)
}

let canvas: CGFloat = 1024
let body: CGFloat = 824
let cornerRadius: CGFloat = 185.4

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("can't read \(arguments[1])\n".utf8))
    exit(1)
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { exit(1) }

let rect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)
let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect).cgPath
context.interpolationQuality = .high
context.addPath(shape)
context.clip()
context.draw(artwork, in: rect)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: arguments[2]) as CFURL, "public.png" as CFString, 1, nil
      ) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
