import SwiftUI

/// A face becomes a rotating set of rings, then resolves to a check or a dimmed face.
/// Everything is drawn from paths; its clock belongs to the view, not the activity model.
struct FaceCheckEmblem: View {
    let phase: FaceCheckLiveActivity.Phase
    var animates = true
    /// Elapsed seconds within this phase, for deterministic previews and frame comparisons.
    var progress: Double? = nil

    nonisolated static let tint = Color(red: 49.0 / 255, green: 152.0 / 255, blue: 251.0 / 255)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
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
            let elapsed = progress ?? (playback.enabled ? max(0, clock.date.timeIntervalSince(startedAt)) : restingTime)
            Canvas(rendersAsynchronously: true) { context, size in
                FaceEmblemDrawing.draw(phase: phase, time: elapsed, in: size, context: &context)
            }
        }
        .accessibilityHidden(true)
        .task(id: playback) {
            startedAt = Date()
            playing = playback.enabled && !playback.overridden && phase != .hidden && phase != .preparing
            guard playing, phase != .scanning else { return }
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            playing = false
        }
    }

    private var restingTime: Double {
        switch phase {
        case .saved, .recognized, .failed: 1.4
        case .hidden, .preparing, .scanning: 0
        }
    }
}

private enum FaceEmblemDrawing {
    private static let line = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
    private static let circlePoints: [SIMD3<Double>] = (0...96).map { index in
        let angle = Double(index) / 96 * .pi * 2
        return SIMD3(cos(angle), sin(angle), 0)
    }

    static func draw(phase: FaceCheckLiveActivity.Phase, time: Double, in size: CGSize, context: inout GraphicsContext) {
        guard phase != .hidden, time.isFinite else { return }
        let edge = min(size.width, size.height)
        guard edge > 0 else { return }
        let rect = CGRect(x: (size.width - edge) / 2, y: (size.height - edge) / 2, width: edge, height: edge)
        switch phase {
        case .hidden:
            break
        case .preparing:
            frame(roundness: 0, gap: 1, in: rect, opacity: 1, context: &context)
            features(in: rect, opacity: 1, context: &context)
        case .scanning:
            let cycle = max(0, time - 0.6) / 0.9
            let breath = (1 - cos(cycle * .pi * 2)) / 2
            let scale = 1 - breath * 0.03
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -rect.midX, y: -rect.midY)
            let opacity = 1 - breath * 0.35
            frame(roundness: 0, gap: 1, in: rect, opacity: opacity, context: &context)
            features(in: rect, opacity: opacity, context: &context)
        case .saved, .recognized:
            result(success: true, time: max(0, time), in: rect, context: &context)
        case .failed:
            result(success: false, time: max(0, time), in: rect, context: &context)
        }
    }

    private static func result(success: Bool, time: Double, in rect: CGRect, context: inout GraphicsContext) {
        let fade = success ? 1 : 1 - 0.6 * ease(time, from: 0.64, to: 0.94)
        if !success, (0.98...1.32).contains(time) {
            let shake = (time - 0.98) / 0.34
            let offset = sin(shake * .pi * 6) * (1 - shake) * rect.width * 0.022
            context.translateBy(x: offset, y: 0)
        }

        let ringsAppear = ease(time, from: 0.19, to: 0.25)
        let ringsDisappear = ease(time, from: 0.66, to: 0.77)
        let outlineOpacity = min(1, 1 - ringsAppear + ringsDisappear) * fade
        let recovery = success ? 0 : ease(time, from: 0.72, to: 0.96)
        let roundness = ease(time, from: 0.08, to: 0.2) * (1 - recovery)
        let gap = max(1 - ease(time, from: 0, to: 0.14), recovery)
        frame(roundness: roundness, gap: gap, in: rect, opacity: outlineOpacity, context: &context)

        let featuresAppear = success ? 0 : ease(time, from: 0.78, to: 0.96)
        let featuresOpacity = max(1 - ease(time, from: 0.025, to: 0.16), featuresAppear) * fade
        features(in: rect, opacity: featuresOpacity, context: &context)

        let ringOpacity = ringsAppear * (1 - ringsDisappear) * fade
        if ringOpacity > 0.001 {
            // Older projected positions make faint trails while each ring changes its plane.
            for (delay, opacity, blur) in [(0.075, 0.13, 0.011), (0.038, 0.2, 0.007)] {
                var trail = context
                trail.addFilter(.blur(radius: rect.width * blur))
                rings(at: max(0.2, time - delay), in: rect, opacity: ringOpacity * opacity, context: &trail)
            }
            rings(at: time, in: rect, opacity: ringOpacity, context: &context)
        }

        if success {
            let amount = ease(time, from: 0.8, to: 1.18)
            if amount > 0 {
                var check = Path()
                check.move(to: point(0.35, 0.52, in: rect))
                check.addLine(to: point(0.47, 0.635, in: rect))
                check.addLine(to: point(0.655, 0.42, in: rect))
                stroke(check.trimmedPath(from: 0, to: amount), in: rect, opacity: 1, context: &context)
            }
        }
    }

    /// Four independent rounded corners close their gaps before the outline becomes circular.
    private static func frame(roundness: Double, gap: Double, in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        guard opacity > 0.001 else { return }
        let x = mix(0.13, 0.12, roundness)
        let y = mix(0.148, 0.12, roundness)
        let corner = mix(0.12, 0.38, roundness)
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

    private struct RingPose: Sendable {
        var x: Double
        var y: Double
        var z: Double
    }

    private static let moments: [Double] = [0.2, 0.32, 0.46, 0.6, 0.77]
    private static let poses: [[RingPose]] = [
        [.init(x: 0, y: 0, z: 0), .init(x: 1.38, y: 0.1, z: -0.32), .init(x: 0.15, y: 1.12, z: 0.37),
         .init(x: 0.1, y: 1.3, z: -0.16), .init(x: 0, y: 0, z: 0)],
        [.init(x: 0, y: 0, z: 0), .init(x: 0.04, y: 1.4, z: -0.05), .init(x: 0.4, y: 1.15, z: -0.15),
         .init(x: -0.2, y: 1.3, z: 0.13), .init(x: 0, y: 0, z: 0)],
        [.init(x: 0, y: 0, z: 0), .init(x: 0.75, y: 0.9, z: 0.65), .init(x: -0.4, y: 0.9, z: 0.5),
         .init(x: 0.22, y: 1.05, z: -0.23), .init(x: 0, y: 0, z: 0)]
    ]

    private static func rings(at time: Double, in rect: CGRect, opacity: Double, context: inout GraphicsContext) {
        let index = min(moments.count - 2, max(0, (moments.lastIndex { $0 <= time } ?? 0)))
        let amount = min(1, max(0, (time - moments[index]) / (moments[index + 1] - moments[index])))
        for ring in 0..<3 {
            // Continuous tangents keep the rings moving through each orientation.
            let pose = RingPose(x: angle(\.x, ring: ring, index: index, amount: amount),
                                y: angle(\.y, ring: ring, index: index, amount: amount),
                                z: angle(\.z, ring: ring, index: index, amount: amount))
            let projected = project(pose, in: rect)
            var outline = Path()
            var front = Path()
            var drawingFront = false
            for (index, vertex) in projected.enumerated() {
                if index == 0 { outline.move(to: vertex.point) }
                else { outline.addLine(to: vertex.point) }
                if vertex.depth >= 0 {
                    if drawingFront { front.addLine(to: vertex.point) }
                    else { front.move(to: vertex.point) }
                    drawingFront = true
                } else { drawingFront = false }
            }
            stroke(outline, in: rect, opacity: opacity * 0.48, context: &context)
            stroke(front, in: rect, opacity: opacity * 0.62, context: &context)
        }
    }

    private static func angle(_ axis: KeyPath<RingPose, Double>, ring: Int, index: Int, amount t: Double) -> Double {
        let previous = max(0, index - 1), next = min(moments.count - 1, index + 2)
        let a = poses[ring][index][keyPath: axis], b = poses[ring][index + 1][keyPath: axis]
        let duration = moments[index + 1] - moments[index]
        let startSlope = (b - poses[ring][previous][keyPath: axis]) / (moments[index + 1] - moments[previous]) * duration
        let endSlope = (poses[ring][next][keyPath: axis] - a) / (moments[next] - moments[index]) * duration
        let square = t * t, cube = square * t
        return (2 * cube - 3 * square + 1) * a + (cube - 2 * square + t) * startSlope
            + (-2 * cube + 3 * square) * b + (cube - square) * endSlope
    }

    private static func project(_ pose: RingPose, in rect: CGRect) -> [(point: CGPoint, depth: Double)] {
        let cx = cos(pose.x), sx = sin(pose.x), cy = cos(pose.y), sy = sin(pose.y), cz = cos(pose.z), sz = sin(pose.z)
        return circlePoints.map { source in
            let y1 = source.y * cx, z1 = source.y * sx
            let x2 = source.x * cy + z1 * sy, z2 = -source.x * sy + z1 * cy
            let x3 = x2 * cz - y1 * sz, y3 = x2 * sz + y1 * cz
            let perspective = 1 / (1 - z2 * 0.16)
            return (CGPoint(x: rect.midX + x3 * perspective * rect.width * 0.38,
                            y: rect.midY + y3 * perspective * rect.height * 0.38), z2)
        }
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
