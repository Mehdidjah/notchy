import SwiftUI

/// A click-through direction cue behind the enrollment panel. The timeline lives only in
/// this drawing leaf; camera/model state is never advanced by a display-frame callback.
struct FaceEnrollmentSweepView: View {
    var direction: Double?
    var sampleTime: TimeInterval? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleDirection: Double?
    @State private var started = Date()

    var body: some View {
        Group {
            if !reduceMotion, let degrees = sampleTime == nil ? visibleDirection : direction {
                if let sampleTime {
                    drawing(degrees: degrees, elapsed: sampleTime)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                        drawing(degrees: degrees, elapsed: timeline.date.timeIntervalSince(started))
                    }
                }
            } else { Color.clear }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: direction) {
            withAnimation(.easeOut(duration: 0.25)) { visibleDirection = nil }
            guard direction != nil, !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            started = Date()
            withAnimation(.easeIn(duration: 0.5)) { visibleDirection = direction }
        }
    }

    private func drawing(degrees: Double, elapsed: TimeInterval) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let stamp = context.resolve(Image(decorative: Self.ribbonImage, scale: 1))
            let cycle = elapsed.truncatingRemainder(dividingBy: 2.3)
            let diagonal = hypot(size.width, size.height)
            let radians = degrees * .pi / 180
            let dx = sin(radians), dy = -cos(radians)
            let acrossX = -dy, acrossY = dx
            for ribbon in 0..<24 {
                let seed = Double(ribbon)
                let delay = Double(ribbon % 7) * 0.028
                let progress = (cycle - delay) / (0.96 + Double(ribbon % 5) * 0.065)
                guard progress > 0, progress < 1 else { continue }
                let brightness = min(1, progress / 0.24) * min(1, (1 - progress) / 0.32)
                let lane = (seed / 23 - 0.5) * diagonal * 1.25
                let advance = (progress - 0.5) * diagonal * 1.8
                let center = CGPoint(x: size.width / 2 + acrossX * lane + dx * advance,
                                     y: size.height / 2 + acrossY * lane + dy * advance)
                let breadth = 38 + Double(ribbon % 4) * 19
                let halfLength = diagonal * (0.32 + Double(ribbon % 3) * 0.07)
                var layer = context
                layer.opacity = brightness
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .degrees(degrees - 90))
                layer.draw(stamp, in: CGRect(x: -halfLength, y: -breadth, width: halfLength * 2, height: breadth * 2))
            }
        }
        .opacity(0.6)
    }

    /// Generated once from smooth falloffs, then transformed by Canvas. Baking the softness
    /// avoids running dozens of full-display blur filters on every animation frame.
    private static let ribbonImage: CGImage = {
        let width = 256, height = 96
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let across = Double(y) / Double(height - 1) * 2 - 1
            let core = exp(-pow((across - 0.05) / 0.36, 2))
            let softness = pow(max(0, 1 - across * across), 2)
            for x in 0..<width {
                let along = sin(Double(x) / Double(width - 1) * .pi)
                let alpha = along * along * softness * 0.8
                let index = (y * width + x) * 4
                rgba[index] = UInt8((0.2 + core * 0.65) * alpha * 255)
                rgba[index + 1] = UInt8((0.5 + core * 0.43) * alpha * 255)
                rgba[index + 2] = UInt8(alpha * 255)
                rgba[index + 3] = UInt8(alpha * 255)
            }
        }
        let data = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: data, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }()
}
