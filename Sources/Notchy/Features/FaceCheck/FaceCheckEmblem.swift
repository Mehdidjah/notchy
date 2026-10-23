import SwiftUI

/// A face becomes a rotating set of rings, then resolves to a check or a dimmed face.
/// Everything is drawn from paths; its clock belongs to the view, not the activity model.
struct FaceCheckEmblem: View {
    let phase: FaceCheckLiveActivity.Phase
    var animates = true
    /// Elapsed seconds within this phase, for deterministic previews and frame comparisons.
    var progress: Double? = nil
    /// A detached pill can include its slide before the first breath begins.
    var scanStartDelay: Double = 0.6

    nonisolated static let tint = Color(red: 49.0 / 255, green: 152.0 / 255, blue: 251.0 / 255)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationClock = FaceCheckEmblemClock()
    @State private var playing = true

    private struct Playback: Equatable {
        var phase: FaceCheckLiveActivity.Phase
        var enabled: Bool
        var overridden: Bool
    }

    private var playback: Playback {
        Playback(phase: phase, enabled: animates && !reduceMotion, overridden: progress != nil)
    }

    var body: some View {
        TimelineView(.animation(paused: !playing || !playback.enabled || playback.overridden)) { clock in
            let phase = phase, source = animationClock, date = clock.date
            let enabled = playback.enabled, isPlaying = playing, elapsed = progress, delay = scanStartDelay
            Canvas(rendersAsynchronously: true) { context, size in
                let frame = source.frame(for: phase, at: date, motionEnabled: enabled, playing: isPlaying,
                                         progress: elapsed, scanStartDelay: delay)
                FaceEmblemDrawing.draw(phase: phase, frame: frame, in: size, context: &context)
            }
        }
        .accessibilityHidden(true)
        .task(id: playback) {
            animationClock.begin(phase, at: Date(), motionEnabled: playback.enabled, scanStartDelay: scanStartDelay)
            playing = playback.enabled && !playback.overridden && phase != .hidden && phase != .preparing
            guard playing, phase != .scanning else { return }
            try? await Task.sleep(for: .seconds(FaceCheckEmblemClock.duration(of: phase)))
            guard !Task.isCancelled else { return }
            playing = false
        }
    }

    static func drawing(phase: FaceCheckLiveActivity.Phase, frame: FaceCheckEmblemClock.Frame) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            FaceEmblemDrawing.draw(phase: phase, frame: frame, in: size, context: &context)
        }
    }
}

/// Stores phase boundaries only. Timeline samples never mutate the activity or the clock.
struct FaceCheckEmblemClock: Sendable {
    struct Frame: Equatable, Sendable {
        var elapsed: Double
        var breath: Double
        var scale: Double { 1 - 0.03 * breath }
        var opacity: Double { 1 - 0.35 * breath }
    }

    private var phase: FaceCheckLiveActivity.Phase?
    private var startedAt = Date.distantPast
    private var inheritedBreath = 0.0

    mutating func begin(_ next: FaceCheckLiveActivity.Phase, at date: Date, motionEnabled: Bool = true,
                        scanStartDelay: Double = 0.6) {
        inheritedBreath = motionEnabled ? breathToCarry(into: next, at: date, scanStartDelay: scanStartDelay) : 0
        phase = next
        startedAt = date
    }

    func frame(for requestedPhase: FaceCheckLiveActivity.Phase, at date: Date, motionEnabled: Bool = true,
               playing: Bool = true, progress: Double? = nil, scanStartDelay: Double = 0.6) -> Frame {
        if let progress {
            return sample(requestedPhase, elapsed: progress, inherited: phase == requestedPhase ? inheritedBreath : 0,
                          scanStartDelay: scanStartDelay)
        }
        guard motionEnabled else { return Frame(elapsed: Self.duration(of: requestedPhase), breath: 0) }
        // The first render can precede the phase-change task. Never reuse the previous phase's time.
        guard phase == requestedPhase else {
            return Frame(elapsed: 0, breath: breathToCarry(into: requestedPhase, at: date, scanStartDelay: scanStartDelay))
        }
        let elapsed = playing ? max(0, date.timeIntervalSince(startedAt)) : Self.duration(of: requestedPhase)
        return sample(requestedPhase, elapsed: elapsed, inherited: inheritedBreath, scanStartDelay: scanStartDelay)
    }

    static func duration(of phase: FaceCheckLiveActivity.Phase) -> Double {
        switch phase {
        case .saved, .recognized: 73.0 / 60
        case .failed: 91.0 / 60
        case .hidden, .preparing, .scanning: 0
        }
    }

    private func breathToCarry(into next: FaceCheckLiveActivity.Phase, at date: Date, scanStartDelay: Double) -> Double {
        guard Self.isResult(next), let phase else { return 0 }
        return sample(phase, elapsed: max(0, date.timeIntervalSince(startedAt)), inherited: inheritedBreath,
                      scanStartDelay: scanStartDelay).breath
    }

    private func sample(_ phase: FaceCheckLiveActivity.Phase, elapsed: Double, inherited: Double,
                        scanStartDelay: Double) -> Frame {
        let breath: Double
        if phase == .scanning {
            breath = FaceCheckEmblemTiming.breath(at: elapsed, delay: scanStartDelay)
        } else if Self.isResult(phase) {
            breath = inherited * (1 - FaceCheckEmblemTiming.curve(elapsed / 0.2, first: 0, second: 0.58))
        } else {
            breath = 0
        }
        return Frame(elapsed: elapsed, breath: breath)
    }

    private static func isResult(_ phase: FaceCheckLiveActivity.Phase) -> Bool {
        phase == .saved || phase == .recognized || phase == .failed
    }
}

private enum FaceEmblemDrawing {
    private static let line = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
    private static let circlePoints: [SIMD2<Double>] = (0..<96).map { index in
        let angle = Double(index) / 96 * .pi * 2
        return SIMD2(cos(angle), sin(angle))
    }

    static func draw(phase: FaceCheckLiveActivity.Phase, frame sample: FaceCheckEmblemClock.Frame, in size: CGSize,
                     context: inout GraphicsContext) {
        let time = sample.elapsed
        guard phase != .hidden, time.isFinite else { return }
        let edge = min(size.width, size.height)
        guard edge > 0 else { return }
        let rect = CGRect(x: (size.width - edge) / 2, y: (size.height - edge) / 2, width: edge, height: edge)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: sample.scale, y: sample.scale)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        context.opacity *= sample.opacity
        switch phase {
        case .hidden:
            break
        case .preparing, .scanning:
            frame(roundness: 0, gap: 1, in: rect, opacity: 1, context: &context)
            features(in: rect, opacity: 1, context: &context)
        case .saved, .recognized:
            result(success: true, time: max(0, time), in: rect, context: &context)
        case .failed:
            result(success: false, time: max(0, time), in: rect, context: &context)
        }
    }

    private static func result(success: Bool, time: Double, in rect: CGRect, context: inout GraphicsContext) {
        let fade = success ? 1 : 1 - 0.6 * ease(time, from: 0.667, to: 0.7)
        if !success {
            context.translateBy(x: failureOffset(at: time) * rect.width, y: 0)
        }

        // Both paths meet at the same circle. Swapping there avoids a dim crossfade.
        let showsRings = time >= 0.233 && time < (success ? 0.75 : 0.733)
        let outlineOpacity = showsRings ? 0 : fade
        let recovery = success ? 0 : ease(time, from: 0.73, to: 0.9)
        let closingRoundness = time < 0.2
            ? 0.64 * pow(min(1, max(0, (time - 0.033) / 0.167)), 1.3)
            : 0.64 + 0.36 * ease(time, from: 0.2, to: 0.233)
        let roundness = closingRoundness * (1 - recovery)
        let gap = max(1 - ease(time, from: 0.05, to: 0.2), recovery)
        frame(roundness: roundness, gap: gap, in: rect, opacity: outlineOpacity, context: &context)

        let featuresAppear = success ? 0 : ease(time, from: 0.775, to: 0.9)
        let featuresOpacity = max(1 - ease(time, from: 0.07, to: 0.2), featuresAppear) * fade
        features(in: rect, opacity: featuresOpacity, context: &context)

        let ringOpacity = showsRings ? fade : 0
        if ringOpacity > 0.001 {
            // Soft, older positions suggest depth without adding more solid rings.
            let trailFade = 1 - ease(time, from: 0.65, to: 0.755)
            for (delay, opacity, blur) in [(0.12, 0.07, 0.018), (0.09, 0.10, 0.015),
                                           (0.06, 0.14, 0.012), (0.03, 0.20, 0.008)] {
                var trail = context
                trail.addFilter(.blur(radius: rect.width * blur))
                rings(at: max(0.233, time - delay), in: rect,
                      opacity: ringOpacity * opacity * trailFade, context: &trail)
            }
            rings(at: time, in: rect, opacity: ringOpacity, context: &context)
        }

        if success {
            let amount = FaceCheckEmblemTiming.curve((time - 0.75) / 0.35, first: 0.3, second: 0.49)
            if amount > 0 {
                var check = Path()
                check.move(to: point(0.362, 0.518, in: rect))
                check.addLine(to: point(0.477, 0.623, in: rect))
                check.addLine(to: point(0.648, 0.413, in: rect))
                stroke(check.trimmedPath(from: 0, to: amount), in: rect, opacity: 1, context: &context)
            }
        }
    }

    /// Four independent rounded corners close their gaps before the outline becomes circular.
    private static func frame(roundness: Double, gap: Double, in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        guard opacity > 0.001 else { return }
        let x = mix(0.13, 0.125, roundness)
        let y = mix(0.148, 0.125, roundness)
        let corner = mix(0.12, 0.375, roundness)
        let radiusX = min(corner, 0.5 - x)
        let radiusY = min(corner, 0.5 - y)
        let open = 0.22 * gap
        let bend = 0.5522847498
        var path = Path()
        for (horizontal, vertical) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            let outerX = horizontal < 0 ? x : 1 - x
            let outerY = vertical < 0 ? y : 1 - y
            let curveX = outerX - horizontal * radiusX
            let curveY = outerY - vertical * radiusY
            path.move(to: point(0.5 + horizontal * open, outerY, in: rect))
            path.addLine(to: point(curveX, outerY, in: rect))
            path.addCurve(
                to: point(outerX, curveY, in: rect),
                control1: point(curveX + horizontal * radiusX * bend, outerY, in: rect),
                control2: point(outerX, curveY + vertical * radiusY * bend, in: rect)
            )
            path.addLine(to: point(outerX, 0.5 + vertical * open, in: rect))
        }
        stroke(path, in: rect, opacity: opacity, context: &context)
    }

    private static func features(in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        guard opacity > 0.001 else { return }
        var face = Path()
        for x in [0.335, 0.68] {
            face.move(to: point(x, 0.326, in: rect))
            face.addLine(to: point(x, 0.422, in: rect))
        }
        face.move(to: point(0.528, 0.326, in: rect))
        face.addLine(to: point(0.46, 0.537, in: rect))
        face.addLine(to: point(0.528, 0.537, in: rect))
        face.move(to: point(0.324, 0.636, in: rect))
        face.addQuadCurve(to: point(0.694, 0.636, in: rect), control: point(0.505, 0.775, in: rect))
        stroke(face, in: rect, opacity: opacity, context: &context)
    }

    /// An ellipse is the screen projection of a circular ring turning in space.
    private struct RingPose: Sendable {
        var x: Double
        var y: Double
        var major: Double
        var minor: Double
        var angle: Double
        var opacity: Double
    }

    private struct RingMoment: Sendable {
        var time: Double
        var pose: RingPose

        init(_ time: Double, minor: Double, angle: Double = 0, x: Double = 0.5, y: Double = 0.5,
             major: Double = 0.375, opacity: Double = 1) {
            self.time = time
            pose = RingPose(x: x, y: y, major: major, minor: minor, angle: angle, opacity: opacity)
        }
    }

    private static let foregroundRing: [RingMoment] = [
        .init(0.233, minor: 0.375, y: 0.495),
        .init(0.267, minor: 0.308, angle: -0.16, y: 0.465),
        .init(0.300, minor: 0.193, angle: -0.22, y: 0.466),
        .init(0.333, minor: 0.035, angle: -0.27, x: 0.52, y: 0.49, opacity: 0.78),
        .init(0.367, minor: 0.12, angle: -0.57, x: 0.54, opacity: 0.82),
        .init(0.400, minor: 0.214, angle: -1.01, x: 0.584, y: 0.526, opacity: 0.95),
        .init(0.433, minor: 0.24, angle: -1.38, x: 0.55, y: 0.52, opacity: 0.85),
        .init(0.467, minor: 0.364, angle: -1.53, x: 0.512),
        .init(0.500, minor: 0.269, angle: -1.61, x: 0.519, y: 0.496),
        .init(0.533, minor: 0.13, angle: -1.32, x: 0.44, y: 0.474, opacity: 0.9),
        .init(0.567, minor: 0.222, angle: -1.34, x: 0.454, y: 0.465, major: 0.358, opacity: 0.95),
        .init(0.600, minor: 0.301, angle: -1.38, x: 0.461, y: 0.454, major: 0.347),
        .init(0.633, minor: 0.344, angle: -1.4, x: 0.47, y: 0.453, major: 0.347),
        .init(0.700, minor: 0.365, angle: -1.4, x: 0.492, y: 0.481, major: 0.365),
        .init(0.750, minor: 0.375, angle: -1.4)
    ]

    private static let backgroundRing: [RingMoment] = [
        .init(0.233, minor: 0.375, angle: 1.4),
        .init(0.267, minor: 0.30, angle: 1.4, x: 0.47, y: 0.52),
        .init(0.300, minor: 0.235, angle: 1.4, x: 0.465, y: 0.515),
        .init(0.333, minor: 0.095, angle: 1.5, x: 0.46),
        .init(0.367, minor: 0.008, angle: 1.6, x: 0.47),
        .init(0.400, minor: 0.20, angle: 2.15, x: 0.56, y: 0.51),
        .init(0.433, minor: 0.26, angle: 1.7, x: 0.535, y: 0.51),
        .init(0.467, minor: 0.008, angle: 1.28, x: 0.475),
        .init(0.500, minor: 0.075, angle: 1.6, x: 0.43, y: 0.49),
        .init(0.533, minor: 0.08, angle: 1.58, x: 0.514, y: 0.495),
        .init(0.600, minor: 0.235, angle: 1.5, x: 0.46, y: 0.52, major: 0.395),
        .init(0.667, minor: 0.32, angle: 1.5, x: 0.486, y: 0.503, major: 0.38),
        .init(0.733, minor: 0.375, angle: 1.5)
    ]

    private static func rings(at time: Double, in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        let back = pose(at: time, moments: backgroundRing)
        let front = pose(at: time, moments: foregroundRing)
        let depthFade = 1 - ease(time, from: 0.65, to: 0.75)
        stroke(project(back, in: rect), in: rect, opacity: opacity * 0.62 * depthFade, context: &context)
        stroke(project(front, in: rect), in: rect, opacity: opacity * front.opacity, context: &context)
    }

    private static func pose(at time: Double, moments: [RingMoment]) -> RingPose {
        let index = min(moments.count - 2, max(0, moments.lastIndex { $0.time <= time } ?? 0))
        let amount = min(1, max(0, (time - moments[index].time) / (moments[index + 1].time - moments[index].time)))
        func value(_ axis: KeyPath<RingPose, Double>) -> Double {
            interpolate(axis, moments: moments, index: index, amount: amount)
        }
        return RingPose(x: value(\.x), y: value(\.y), major: value(\.major), minor: max(0.005, value(\.minor)),
                        angle: value(\.angle), opacity: min(1, max(0, value(\.opacity))))
    }

    private static func interpolate(_ axis: KeyPath<RingPose, Double>, moments: [RingMoment], index: Int,
                                    amount t: Double) -> Double {
        let previous = max(0, index - 1), next = min(moments.count - 1, index + 2)
        let a = moments[index].pose[keyPath: axis], b = moments[index + 1].pose[keyPath: axis]
        let duration = moments[index + 1].time - moments[index].time
        let startSlope = (b - moments[previous].pose[keyPath: axis]) / (moments[index + 1].time - moments[previous].time) * duration
        let endSlope = (moments[next].pose[keyPath: axis] - a) / (moments[next].time - moments[index].time) * duration
        let square = t * t, cube = square * t
        return (2 * cube - 3 * square + 1) * a + (cube - 2 * square + t) * startSlope
            + (-2 * cube + 3 * square) * b + (cube - square) * endSlope
    }

    private static func project(_ pose: RingPose, in rect: CGRect) -> Path {
        let cosine = cos(pose.angle), sine = sin(pose.angle)
        var path = Path()
        for (index, source) in circlePoints.enumerated() {
            let x = source.x * pose.major, y = source.y * pose.minor
            let vertex = point(pose.x + x * cosine - y * sine, pose.y + x * sine + y * cosine, in: rect)
            if index == 0 { path.move(to: vertex) }
            else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }

    private static func failureOffset(at time: Double) -> Double {
        let times = [0.8, 0.9, 1.033, 1.133, 1.267, 1.433]
        let offsets = [0.0, 0.043, -0.066, 0.027, -0.047, 0.0]
        guard time > times[0], time < times[times.count - 1] else { return 0 }
        let index = min(times.count - 2, times.lastIndex { $0 <= time } ?? 0)
        let fraction = (time - times[index]) / (times[index + 1] - times[index])
        // A short ease at each reversal keeps the motion crisp without discontinuities.
        return mix(offsets[index], offsets[index + 1], FaceCheckEmblemTiming.curve(fraction, first: 0.15, second: 0.85))
    }

    private static func stroke(_ path: Path, in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        var style = line
        style.lineWidth = rect.width * 0.052
        context.stroke(path, with: .color(FaceCheckEmblem.tint.opacity(opacity)), style: style)
    }

    private static func point(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    private static func mix(_ start: Double, _ end: Double, _ amount: Double) -> Double {
        start + (end - start) * amount
    }

    private static func ease(_ time: Double, from start: Double, to end: Double) -> Double {
        let t = min(1, max(0, (time - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
}

private enum FaceCheckEmblemTiming {
    /// Each 400 ms ease-in-out is followed by a 50 ms hold before reversing.
    static func breath(at time: Double, delay: Double) -> Double {
        let start = delay.isFinite ? max(0, delay) : 0.6
        guard time > start else { return 0 }
        let cycle = (time - start).truncatingRemainder(dividingBy: 0.9)
        if cycle < 0.4 { return curve(cycle / 0.4) }
        if cycle < 0.45 { return 1 }
        if cycle < 0.85 { return 1 - curve((cycle - 0.45) / 0.4) }
        return 0
    }

    /// Evaluate the x-inverse of a cubic timing curve, with y control points at 0 and 1.
    static func curve(_ fraction: Double, first: Double = 0.42, second: Double = 0.58) -> Double {
        let fraction = min(1, max(0, fraction))
        guard fraction > 0, fraction < 1 else { return fraction }
        var lower = 0.0, upper = 1.0
        for _ in 0..<14 {
            let t = (lower + upper) / 2, inverse = 1 - t
            let x = 3 * inverse * inverse * t * first + 3 * inverse * t * t * second + t * t * t
            if x < fraction { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return t * t * (3 - 2 * t)
    }
}
