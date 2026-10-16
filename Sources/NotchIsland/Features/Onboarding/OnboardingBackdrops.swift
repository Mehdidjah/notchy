import AppKit
import QuartzCore
import SwiftUI

/// An `NSVisualEffectView` that blurs whatever sits behind the window.
struct OnboardingVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // Stay vibrant even when the window is not key, and use the emphasized variant.
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

extension View {
    /// The standard onboarding page backdrop (Atoll: under-window background, behind window).
    func onboardingPageBackground() -> some View {
        background(
            OnboardingVisualEffect(material: .underWindowBackground)
                .ignoresSafeArea()
        )
    }
}

/// A field of slowly drifting sparkles drawn with a Core Animation emitter.
///
/// Matches Atoll's welcome-page emitter: a rectangular surface emitter, 20 particles a second
/// (the initial 50 is overridden once the view has a size), 5-s lifetime, velocity 10 ± 5 in
/// every direction, scale 0.2 ± 0.1, fading at 0.5 a second with a y acceleration of 10 pt/s².
/// Like Atoll's emitter view this one is not flipped, so that acceleration lifts the sparkles.
struct OnboardingSparkleField: NSViewRepresentable {
    func makeNSView(context: Context) -> OnboardingSparkleNSView {
        OnboardingSparkleNSView(frame: .zero)
    }

    func updateNSView(_ view: OnboardingSparkleNSView, context: Context) {}
}

final class OnboardingSparkleNSView: NSView {
    static let settledBirthRate: Float = 20
    static let initialBirthRate: Float = 50

    private let emitter = CAEmitterLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureEmitter()
    }

    required init?(coder: NSCoder) { nil }

    private func configureEmitter() {
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        emitter.renderMode = .oldestFirst

        let sparkle = CAEmitterCell()
        sparkle.contents = Self.sparkleImage
        sparkle.contentsScale = Self.sparkleImageScale
        sparkle.birthRate = Self.initialBirthRate
        sparkle.lifetime = 5
        sparkle.velocity = 10
        sparkle.velocityRange = 5
        sparkle.emissionRange = .pi * 2
        sparkle.scale = 0.2
        sparkle.scaleRange = 0.1
        sparkle.alphaSpeed = -0.5
        sparkle.yAcceleration = 10
        emitter.emitterCells = [sparkle]
        layer?.addSublayer(emitter)
        layoutEmitter()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutEmitter()
    }

    private func layoutEmitter() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = bounds
        emitter.emitterSize = bounds.size
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.emitterCells?.first?.birthRate = Self.settledBirthRate
        CATransaction.commit()
    }

    /// Point size of the particle artwork (Atoll's "sparkle" is a 26-pt square).
    static let sparkleSide: CGFloat = 26
    /// The artwork is drawn at 2x and the cell is told so, keeping it 26 pt on screen.
    static let sparkleImageScale: CGFloat = 2

    /// A white dot of radius 3 pt with a faint white halo around it (25 % at the dot's edge,
    /// fading out about 7 pt further), centred in a 26-pt square.
    static let sparkleImage: CGImage? = {
        let pixels = Int(sparkleSide * sparkleImageScale)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: sparkleImageScale, y: sparkleImageScale)
        let centre = CGPoint(x: sparkleSide / 2, y: sparkleSide / 2)
        let dotRadius: CGFloat = 3

        // Halo.
        let colors = [
            CGColor(gray: 1, alpha: 0.25),
            CGColor(gray: 1, alpha: 0.12),
            CGColor(gray: 1, alpha: 0)
        ] as CFArray
        if let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.45, 1]) {
            context.drawRadialGradient(
                halo,
                startCenter: centre, startRadius: dotRadius,
                endCenter: centre, endRadius: dotRadius + 8,
                options: []
            )
        }

        // Dot.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: centre.x - dotRadius,
            y: centre.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        return context.makeImage()
    }()
}
