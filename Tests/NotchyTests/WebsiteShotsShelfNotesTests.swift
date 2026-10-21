import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Notchy

/// The website's Shelf and Notes tabs, each built on its own store in a temporary folder:
/// the shelf holds files drawn here (a photo, a PDF brief, a folder, release notes) beside a
/// text snippet and a link; the notes are a small made-up library led by a pinned checklist.
@MainActor
@Suite(.serialized)
struct WebsiteShotsShelfNotesTests {
    // MARK: Shelf

    @Test func shelfTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let root = try WebsiteShots.temporaryDirectory("shelf")
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try ShelfSampleFiles(root: root.appendingPathComponent("Desktop", isDirectory: true))
        let store = ShelfStore(
            persistence: nil,
            temporaryFiles: ShelfTemporaryFileStore(rootDirectory: root.appendingPathComponent("Drops", isDirectory: true))
        )
        let settings = ShelfSettings(defaults: try WebsiteShots.defaults())
        // The share square's AirDrop glyph is the system's full-colour AirDrop icon, which
        // draws as a solid square once tinted; the share menu target keeps it a clean symbol.
        settings.shareTarget = .shareMenu
        // About four tiles fit beside the share square: two files, a snippet and a link up
        // front, more files further along the row.
        store.add([
            try ShelfItem.file(at: files.hero),
            try ShelfItem.file(at: files.brief),
            .text("Call Ana about the launch"),
            .link(try #require(URL(string: "https://notchyy.vercel.app"))),
            try ShelfItem.file(at: files.brandFolder),
            try ShelfItem.file(at: files.releaseNotes),
        ])
        #expect(store.count == 6)

        // Quick Look thumbnails are made in the background; have them ready before drawing.
        for url in files.all {
            _ = await ShelfThumbnailCache.shared.thumbnail(for: url)
        }

        let island = try WebsiteIsland()
        island.open(.shelf)
        #expect(island.model.selectedTab == .shelf)
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-shelf.png"),
            content: { tab in
                guard tab == .shelf else { return nil }
                return AnyView(NotchShelfTabView(model: island.model, store: store, settings: settings))
            },
            settle: .milliseconds(1500)
        )
    }

    // MARK: Notes

    @Test func notesTab() async throws {
        guard let output = WebsiteShots.output else { return }
        let root = try WebsiteShots.temporaryDirectory("notes")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try NotesSampleLibrary(directory: root.appendingPathComponent("Notes", isDirectory: true))
        let controller = library.controller
        #expect(!library.settings.appleNotesSyncEnabled)

        let island = try WebsiteIsland()
        island.open(.notes)
        #expect(island.model.selectedTab == .notes)
        // The list is the tab's fullest view at the island's standard height: with more than
        // three notes it shows two columns of colour-coded notes, the pinned one first.
        try await island.renderOpen(
            to: output.appendingPathComponent("tab-notes.png"),
            content: { tab in
                guard tab == .notes else { return nil }
                return AnyView(NotchNotesTabView(model: island.model, controller: controller))
            }
        )
        #expect(!controller.isEditing)
        #expect(library.store.notes.first?.title == "Launch checklist")
        // Let the queued library writes land before the folder is removed.
        await library.store.flush()
    }
}

// MARK: - Shelf sample files

/// Made-up files for the shelf, drawn here so their Quick Look thumbnails look like real work.
@MainActor
private struct ShelfSampleFiles {
    let hero: URL
    let brief: URL
    let brandFolder: URL
    let releaseNotes: URL

    var all: [URL] { [hero, brief, brandFolder, releaseNotes] }

    init(root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        hero = root.appendingPathComponent("Hero.png")
        try Self.landscapePNG(width: 1600, height: 1000).write(to: hero)

        brief = root.appendingPathComponent("Launch brief.pdf")
        try Self.briefPDF().write(to: brief)

        brandFolder = root.appendingPathComponent("Brand assets", isDirectory: true)
        try fileManager.createDirectory(at: brandFolder, withIntermediateDirectories: true)
        try Self.landscapePNG(width: 400, height: 250).write(to: brandFolder.appendingPathComponent("Cover.png"))
        try Data("Primary #E46642\nInk #1B1D2B\nSand #F4E9DA\n".utf8)
            .write(to: brandFolder.appendingPathComponent("Colours.txt"))

        releaseNotes = root.appendingPathComponent("Release notes.md")
        try Data("""
        # Release notes

        ## What's new
        - Drop files on the notch to park them on the shelf
        - Notes open in place, with colours and pins
        - Timer keeps counting when the island is closed

        ## Fixes
        - The island no longer flickers when a display wakes
        - Faster thumbnails for large photos
        """.utf8).write(to: releaseNotes)
    }

    /// A dusk landscape: a sky gradient, a low sun and three ranges of hills over a lake.
    static func landscapePNG(width: Int, height: Int) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let w = CGFloat(width), h = CGFloat(height)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        }

        // Sky, from deep blue at the top to peach on the horizon (y grows upwards).
        let sky = try #require(CGGradient(
            colorsSpace: space,
            colors: [
                color(1.00, 0.78, 0.55), color(0.97, 0.52, 0.45), color(0.62, 0.32, 0.55),
                color(0.24, 0.20, 0.45), color(0.10, 0.12, 0.30),
            ] as CFArray,
            locations: [0.30, 0.45, 0.62, 0.82, 1.0]
        ))
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])

        // A low sun with a soft glow.
        let sun = CGPoint(x: w * 0.64, y: h * 0.47)
        let glow = try #require(CGGradient(
            colorsSpace: space,
            colors: [color(1, 0.93, 0.75, 0.9), color(1, 0.75, 0.55, 0)] as CFArray,
            locations: [0, 1]
        ))
        context.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: w * 0.28, options: [])
        context.setFillColor(color(1, 0.95, 0.82))
        context.fillEllipse(in: CGRect(x: sun.x - w * 0.055, y: sun.y - w * 0.055, width: w * 0.11, height: w * 0.11))

        // Three ranges of hills, nearer ones darker and lower.
        func ridge(base: CGFloat, height amplitude: CGFloat, waves: [(CGFloat, CGFloat, CGFloat)], fill: CGColor) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            let steps = 160
            for step in 0 ... steps {
                let x = w * CGFloat(step) / CGFloat(steps)
                let t = x / w
                var y = base
                for (frequency, phase, weight) in waves {
                    y += amplitude * weight * sin(t * frequency * .pi * 2 + phase)
                }
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(fill)
            context.fillPath()
        }
        ridge(base: h * 0.44, height: h * 0.07, waves: [(1.3, 0.4, 1), (3.1, 1.2, 0.45), (7.0, 0.3, 0.12)], fill: color(0.55, 0.33, 0.52))
        ridge(base: h * 0.36, height: h * 0.08, waves: [(0.9, 2.2, 1), (2.6, 0.1, 0.5), (6.2, 1.9, 0.14)], fill: color(0.34, 0.22, 0.42))
        ridge(base: h * 0.27, height: h * 0.06, waves: [(1.6, 4.0, 1), (4.3, 2.4, 0.35), (9.0, 0.8, 0.1)], fill: color(0.17, 0.14, 0.29))

        // A lake catching the sky, with a streak of sunlight.
        let lakeTop = h * 0.2
        let lake = try #require(CGGradient(
            colorsSpace: space,
            colors: [color(0.08, 0.09, 0.20), color(0.42, 0.27, 0.45)] as CFArray,
            locations: [0, 1]
        ))
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: w, height: lakeTop))
        context.drawLinearGradient(lake, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: lakeTop), options: [])
        context.setFillColor(color(1, 0.85, 0.65, 0.55))
        for row in 0 ..< 7 {
            let y = lakeTop - CGFloat(row + 1) * h * 0.024
            let half = w * (0.07 - CGFloat(row) * 0.008)
            context.fill(CGRect(x: sun.x - half, y: y, width: half * 2, height: h * 0.006))
        }
        context.restoreGState()

        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    /// A one-page brief: a coloured header, the title, a few paragraphs and a milestone row.
    static func briefPDF() throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &page, [kCGPDFContextTitle: "Launch brief"] as CFDictionary))
        context.beginPDFPage(nil)

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(page)

        // Header band.
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let band = try #require(CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 0.98, green: 0.45, blue: 0.33, alpha: 1),
                CGColor(srgbRed: 0.85, green: 0.30, blue: 0.55, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ))
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 612, width: 612, height: 180))
        context.drawLinearGradient(band, start: CGPoint(x: 0, y: 700), end: CGPoint(x: 612, y: 700), options: [])
        context.restoreGState()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }

        func draw(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, in rect: CGRect) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = size * 0.35
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]).draw(with: rect, options: [.usesLineFragmentOrigin])
        }

        draw("PRODUCT LAUNCH", size: 13, weight: .semibold, color: .white.withAlphaComponent(0.85), in: CGRect(x: 48, y: 720, width: 516, height: 22))
        draw("Launch brief", size: 44, weight: .bold, color: .white, in: CGRect(x: 48, y: 650, width: 516, height: 60))
        draw("Version 2.0  ·  Lisbon studio  ·  Ships 14 November", size: 14, weight: .medium, color: .white.withAlphaComponent(0.9), in: CGRect(x: 48, y: 626, width: 516, height: 22))

        let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.17, alpha: 1)
        let body = NSColor(srgbRed: 0.33, green: 0.34, blue: 0.40, alpha: 1)
        draw("Goal", size: 20, weight: .semibold, color: ink, in: CGRect(x: 48, y: 560, width: 516, height: 28))
        draw(
            "Show how the notch becomes a place to park files, jot notes and keep an eye on timers without leaving the app you are in. One clear story, three short clips.",
            size: 13, color: body, in: CGRect(x: 48, y: 486, width: 516, height: 72)
        )
        draw("Audience", size: 20, weight: .semibold, color: ink, in: CGRect(x: 48, y: 440, width: 516, height: 28))
        draw(
            "Designers and developers on recent MacBooks who live in full-screen apps and keep losing track of downloads, snippets and meetings.",
            size: 13, color: body, in: CGRect(x: 48, y: 382, width: 516, height: 56)
        )

        // Milestones.
        draw("Milestones", size: 20, weight: .semibold, color: ink, in: CGRect(x: 48, y: 330, width: 516, height: 28))
        let milestones = [("Copy final", "3 Nov"), ("Press kit", "7 Nov"), ("Beta build", "10 Nov"), ("Launch", "14 Nov")]
        let dots = [
            NSColor(srgbRed: 0.98, green: 0.45, blue: 0.33, alpha: 1), NSColor(srgbRed: 0.95, green: 0.65, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.35, green: 0.62, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.85, green: 0.30, blue: 0.55, alpha: 1),
        ]
        context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 60, y: 300))
        context.addLine(to: CGPoint(x: 552, y: 300))
        context.strokePath()
        for (index, milestone) in milestones.enumerated() {
            let x = 60 + CGFloat(index) * 164
            context.setFillColor(dots[index].cgColor)
            context.fillEllipse(in: CGRect(x: x - 8, y: 292, width: 16, height: 16))
            draw(milestone.0, size: 13, weight: .semibold, color: ink, in: CGRect(x: x - 12, y: 252, width: 140, height: 20))
            draw(milestone.1, size: 12, color: body, in: CGRect(x: x - 12, y: 234, width: 140, height: 18))
        }

        // Contact block.
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.95, blue: 0.97, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 48, y: 96, width: 516, height: 104), cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.fillPath()
        draw("Owner", size: 12, weight: .semibold, color: body, in: CGRect(x: 72, y: 166, width: 200, height: 18))
        draw("Ana Ribeiro, product", size: 15, weight: .medium, color: ink, in: CGRect(x: 72, y: 144, width: 240, height: 22))
        draw("Reviewers", size: 12, weight: .semibold, color: body, in: CGRect(x: 320, y: 166, width: 200, height: 18))
        draw("Sam Okafor, Leo Martins", size: 15, weight: .medium, color: ink, in: CGRect(x: 320, y: 144, width: 240, height: 22))

        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

// MARK: - Notes sample library

/// A notes library in a temporary folder with its own settings and sync switched off, so
/// nothing reaches the user's notes or the Notes app.
@MainActor
private struct NotesSampleLibrary {
    let store: NotesStore
    let settings: NotesSettings
    let controller: NotesTabController

    init(directory: URL) throws {
        let clock = NotesSampleClock()
        let store = NotesStore(directory: directory, now: { clock.now })
        let settings = NotesSettings(defaults: try WebsiteShots.defaults())
        let sync = AppleNotesSyncManager(store: store, settings: settings, scripting: SilentAppleNotes())
        self.store = store
        self.settings = settings
        controller = NotesTabController(store: store, settings: settings, layout: NotesLayoutState(), sync: sync)

        let base = Date()
        func save(_ title: String, _ content: String, color: Int, minutesAgo: Double, pinned: Bool = false) {
            clock.now = base.addingTimeInterval(-minutesAgo * 60)
            let id = UUID()
            store.save(id: id, title: title, content: content, colorIndex: color, image: .unchanged)
            if pinned { store.togglePin(id: id) }
        }
        // Palette: yellow, blue, red, green, purple, orange.
        save("Lisbon trip", "Flight Thu 9:40 · hotel by the river · dinner with Sam on Friday", color: 2, minutesAgo: 60 * 52)
        save("Interview questions", "What did you ship last that you're proud of? How do you like to get feedback?", color: 4, minutesAgo: 60 * 26)
        save("Groceries", "Oat milk, lemons, sourdough, coffee beans, basil", color: 5, minutesAgo: 190)
        save("Ideas for the landing page", "Open the island on hover in the hero. Short loops of the shelf and timer.", color: 1, minutesAgo: 64)
        save(
            "Launch checklist",
            "✓  Film the walkthrough video\n✓  Update the screenshots\n○  Send the press kit to Ana\n○  Publish on Friday",
            color: 3,
            minutesAgo: 12,
            pinned: true
        )
    }
}

@MainActor
private final class NotesSampleClock {
    var now = Date()
}

/// Stands in for the Notes app; sync is off, so it is never asked anything.
private struct SilentAppleNotes: AppleNotesScripting {
    func fetchNotes(scope: AppleNotesSyncScope) async throws -> [RemoteAppleNote] { [] }
    func createNote(_ payload: AppleNotesPayload) async throws -> String { "" }
    func updateNote(id: String, with payload: AppleNotesPayload) async throws -> Bool { false }
    func deleteNote(id: String) async throws {}
}
