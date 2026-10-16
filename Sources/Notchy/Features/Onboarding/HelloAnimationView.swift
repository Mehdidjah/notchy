import SwiftUI

/// "hello" written as one continuous cursive stroke.
///
/// The lettering is a hand-placed list of knots on a 195 x 100 design grid, joined with a
/// centripetal Catmull-Rom spline (no cusps or loops between knots) and stretched to fill the
/// rect, so it can be drawn at any size and trimmed from start to end.
struct OnboardingHelloShape: Shape {
    /// Knots on the design grid, y pointing down: lead-in, h, e, l, l, o, exit flourish.
    static let knots: [CGPoint] = [
        // Lead-in rising into the h.
        CGPoint(x: 0, y: 92), CGPoint(x: 14, y: 72), CGPoint(x: 26, y: 40), CGPoint(x: 33, y: 14),
        // h: ascender loop, then down the stem.
        CGPoint(x: 31, y: 4), CGPoint(x: 25, y: 8), CGPoint(x: 21, y: 34), CGPoint(x: 19, y: 64),
        CGPoint(x: 18, y: 92),
        // h: shoulder.
        CGPoint(x: 23, y: 70), CGPoint(x: 31, y: 54), CGPoint(x: 39, y: 52), CGPoint(x: 44, y: 62),
        CGPoint(x: 45, y: 80), CGPoint(x: 49, y: 91),
        // e.
        CGPoint(x: 58, y: 86), CGPoint(x: 67, y: 74), CGPoint(x: 72, y: 62), CGPoint(x: 69, y: 52),
        CGPoint(x: 61, y: 55), CGPoint(x: 57, y: 68), CGPoint(x: 59, y: 84), CGPoint(x: 66, y: 92),
        CGPoint(x: 77, y: 88),
        // First l.
        CGPoint(x: 88, y: 70), CGPoint(x: 97, y: 42), CGPoint(x: 102, y: 16), CGPoint(x: 99, y: 4),
        CGPoint(x: 93, y: 8), CGPoint(x: 89, y: 36), CGPoint(x: 88, y: 66), CGPoint(x: 90, y: 86),
        CGPoint(x: 96, y: 92), CGPoint(x: 106, y: 87),
        // Second l.
        CGPoint(x: 117, y: 68), CGPoint(x: 126, y: 40), CGPoint(x: 131, y: 16), CGPoint(x: 128, y: 4),
        CGPoint(x: 122, y: 8), CGPoint(x: 118, y: 36), CGPoint(x: 117, y: 66), CGPoint(x: 119, y: 86),
        CGPoint(x: 125, y: 92), CGPoint(x: 135, y: 87),
        // o.
        CGPoint(x: 144, y: 72), CGPoint(x: 152, y: 58), CGPoint(x: 162, y: 53), CGPoint(x: 171, y: 60),
        CGPoint(x: 172, y: 76), CGPoint(x: 165, y: 89), CGPoint(x: 155, y: 91), CGPoint(x: 149, y: 81),
        CGPoint(x: 152, y: 64), CGPoint(x: 161, y: 55),
        // Exit flourish.
        CGPoint(x: 172, y: 56), CGPoint(x: 184, y: 52), CGPoint(x: 195, y: 46)
    ]

    static let designSize = CGSize(width: 195, height: 100)

    func path(in rect: CGRect) -> Path {
        let points = Self.knots.map { knot in
            CGPoint(
                x: rect.minX + knot.x / Self.designSize.width * rect.width,
                y: rect.minY + knot.y / Self.designSize.height * rect.height
            )
        }
        var path = Path()
        let segments = Self.cubicSegments(through: points)
        guard let first = segments.first else { return path }
        path.move(to: first.start)
        for segment in segments {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
        return path
    }

    struct Segment: Equatable {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint
    }

    /// Converts a centripetal Catmull-Rom spline through `points` into cubic Bezier segments.
    /// End segments reuse their end point as the missing neighbour.
    static func cubicSegments(through points: [CGPoint]) -> [Segment] {
        guard points.count > 1 else { return [] }
        func knotSpacing(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (hypot(b.x - a.x, b.y - a.y)).squareRoot()
        }
        var segments: [Segment] = []
        segments.reserveCapacity(points.count - 1)
        for index in 0..<(points.count - 1) {
            let before = points[max(0, index - 1)]
            let start = points[index]
            let end = points[index + 1]
            let after = points[min(points.count - 1, index + 2)]
            let leading = knotSpacing(before, start)
            let middle = knotSpacing(start, end)
            let trailing = knotSpacing(end, after)

            let control1: CGPoint
            if leading < 0.0001 {
                control1 = CGPoint(x: start.x + (end.x - start.x) / 3, y: start.y + (end.y - start.y) / 3)
            } else {
                let a = leading * leading
                let b = middle * middle
                let weight = 2 * a + 3 * leading * middle + b
                let divisor = 3 * leading * (leading + middle)
                control1 = CGPoint(
                    x: (a * end.x - b * before.x + weight * start.x) / divisor,
                    y: (a * end.y - b * before.y + weight * start.y) / divisor
                )
            }

            let control2: CGPoint
            if trailing < 0.0001 {
                control2 = CGPoint(x: end.x - (end.x - start.x) / 3, y: end.y - (end.y - start.y) / 3)
            } else {
                let a = trailing * trailing
                let b = middle * middle
                let weight = 2 * a + 3 * trailing * middle + b
                let divisor = 3 * trailing * (trailing + middle)
                control2 = CGPoint(
                    x: (a * start.x - b * after.x + weight * end.x) / divisor,
                    y: (a * start.y - b * after.y + weight * end.y) / divisor
                )
            }
            segments.append(Segment(start: start, control1: control1, control2: control2, end: end))
        }
        return segments
    }
}

/// The visible slice of a stroke that writes itself and is then chased away by its own tail.
///
/// The head travels the whole path over the animation; the tail waits until half-way and then
/// moves twice as fast, so the stroke is complete for a moment around the middle and has gone
/// entirely when the head arrives.
struct OnboardingTraceWindow: Equatable {
    var progress: Double

    var head: Double { min(1, max(0, progress)) }
    var tail: Double { min(head, max(0, progress * 2 - 1)) }
}

/// Draws `shape` between the trace window's tail and head with a soft neon glow: a crisp core
/// half the line width, wrapped in two blurred copies at full width.
struct OnboardingGlowingTrace<StrokeShape: Shape, Fill: ShapeStyle>: View, Animatable {
    var progress: Double
    var shape: StrokeShape
    var fill: Fill
    var lineWidth: CGFloat = 8
    var blurRadius: CGFloat = 8
    /// Draws the whole stroke regardless of progress (used when motion is reduced).
    var showsWholeStroke = false

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let window = OnboardingTraceWindow(progress: progress)
        let visible = showsWholeStroke
            ? shape.trim(from: 0, to: 1)
            : shape.trim(from: window.tail, to: window.head)
        let core = StrokeStyle(lineWidth: lineWidth / 2, lineCap: .round)
        let halo = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            visible.stroke(fill, style: core)
            visible.stroke(fill, style: halo).blur(radius: blurRadius)
            visible.stroke(fill, style: halo).blur(radius: blurRadius / 2)
        }
    }
}

extension LinearGradient {
    /// The rainbow the hello is painted with, left to right.
    static var onboardingHello: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .blue, location: 0),
                .init(color: .purple, location: 0.2),
                .init(color: .red, location: 0.4),
                .init(color: .mint, location: 0.5),
                .init(color: .indigo, location: 0.7),
                .init(color: .pink, location: 0.9),
                .init(color: .blue, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// The glowing first-launch "hello", written over four seconds with an ease-in-out curve.
///
/// Shown 200 x 80 in the open notch. Give it any frame; it restarts whenever it
/// appears. Pass `replayToken` changes to restart it while on screen.
struct HelloAnimationView: View {
    var duration: Double = 4
    var lineWidth: CGFloat = 8
    var blurRadius: CGFloat = 8
    var replayToken: Int = 0

    @State private var progress: Double = 0
    @State private var wordOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingGlowingTrace(
            progress: progress,
            shape: OnboardingHelloShape(),
            fill: LinearGradient.onboardingHello,
            lineWidth: lineWidth,
            blurRadius: blurRadius,
            showsWholeStroke: reduceMotion
        )
        .opacity(wordOpacity)
        .accessibilityElement()
        .accessibilityLabel("hello")
        .onAppear(perform: play)
        .onChange(of: replayToken) { _, _ in play() }
    }

    private func play() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        if reduceMotion {
            // Show the whole word and simply fade it in, without the writing motion.
            withTransaction(reset) { wordOpacity = 0 }
            withAnimation(.easeInOut(duration: 0.4)) { wordOpacity = 1 }
            return
        }
        withTransaction(reset) { wordOpacity = 1 }
        withAnimation(.easeInOut(duration: duration)) { progress = 1 }
    }
}

/// The hello as it sits in the open island: 200 x 80, 40 pt below centre-top, centred.
struct OnboardingHelloStage: View {
    @ObservedObject var controller: OnboardingHelloController

    init(controller: OnboardingHelloController = .shared) {
        self.controller = controller
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HelloAnimationView(replayToken: controller.replayCount)
                .frame(width: 200, height: 80)
                .padding(.top, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { controller.helloDidAppear() }
    }
}
