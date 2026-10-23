import SwiftUI

/// A single drawing layer for all ticks. Capture and camera events update its small motion
/// snapshot; display refreshes only sample that snapshot inside the asynchronous Canvas.
struct FaceEnrollmentRing: View {
    var counts: [FaceEnrollmentPose: Int]
    var samplesPerPose: Int
    var heading: FaceEnrollmentPresentation.Heading
    var saved: Bool
    var animates: Bool
    @State private var motion = FaceEnrollmentRingMotion()
    @State private var isAnimating = false

    private var input: FaceEnrollmentRingMotion.Input {
        .init(counts: counts, samplesPerPose: samplesPerPose, heading: heading, saved: saved)
    }

    var body: some View {
        let snapshot = motion
        let finalInput = input
        TimelineView(.animation(minimumInterval: 1 / 120, paused: !animates || !isAnimating)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                for tick in 0..<FaceEnrollmentPresentation.tickCount {
                    let value = animates ? snapshot.tick(tick, at: now) : FaceEnrollmentRingMotion.still(tick, input: finalInput)
                    var layer = context
                    layer.translateBy(x: size.width / 2, y: size.height / 2)
                    layer.rotate(by: .degrees(Double(tick) * 4.5))
                    layer.opacity = value.opacity
                    let mark = Path(roundedRect: CGRect(x: -value.width / 2, y: -value.radius - value.length,
                                                       width: value.width, height: value.length), cornerRadius: value.width / 2)
                    layer.fill(mark, with: .color(Color(red: 1 - value.blue * (1 - 52.0 / 255),
                                                        green: 1 - value.blue * (1 - 153.0 / 255), blue: 1)))
                }
            }
        }
        .onChange(of: input, initial: true) { _, input in
            let now = Date.timeIntervalSinceReferenceDate
            motion.update(input, at: now)
            isAnimating = motion.deadline > now
        }
        .task(id: motion.deadline) {
            let remaining = motion.deadline - Date.timeIntervalSinceReferenceDate
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            isAnimating = false
        }
    }
}

struct FaceEnrollmentRingMotion {
    struct Input: Equatable {
        var counts: [FaceEnrollmentPose: Int] = [:]
        var samplesPerPose = 2
        var heading = FaceEnrollmentPresentation.Heading()
        var saved = false
    }
    struct Tick {
        var length: Double
        var width: Double = FaceEnrollmentPresentation.tickWidth
        var radius = 100.0
        var blue: Double
        var opacity = 1.0
    }
    private var input = Input()
    private var capturedAt: [FaceEnrollmentPose: TimeInterval] = [:]
    private var headingFrom = [Double](repeating: 0, count: 80)
    private var headingAt = -Double.infinity
    private var centreAt = -Double.infinity
    private var savedAt: TimeInterval?
    private(set) var deadline = -Double.infinity

    mutating func update(_ next: Input, at time: TimeInterval) {
        if next.heading != input.heading {
            headingFrom = (0..<80).map { emphasis($0, at: time) }
            headingAt = time
            deadline = max(deadline, time + 0.15)
        }
        if (next.counts[.centre] ?? 0) > (input.counts[.centre] ?? 0) {
            centreAt = time
            deadline = max(deadline, time + 0.44)
        } else if (next.counts[.centre] ?? 0) < (input.counts[.centre] ?? 0) {
            centreAt = -.infinity
        }
        for pose in FaceEnrollmentPose.allCases where pose != .centre {
            if (next.counts[pose] ?? 0) >= next.samplesPerPose {
                if (input.counts[pose] ?? 0) < input.samplesPerPose {
                    capturedAt[pose] = time
                    deadline = max(deadline, time + 0.372)
                }
            } else if !next.saved { capturedAt[pose] = nil }
        }
        if next.saved && !input.saved {
            savedAt = time
            deadline = max(deadline, time + 0.766)
        } else if !next.saved { savedAt = nil }
        input = next
    }

    func tick(_ tick: Int, at time: TimeInterval) -> Tick {
        let pose = FaceEnrollmentPresentation.pose(atTick: tick)
        let captured = (input.counts[pose] ?? 0) >= input.samplesPerPose || input.saved
        let capture = captured ? Self.easeOut((time - (capturedAt[pose] ?? -.infinity) - Double(tick % 10) * 0.008) / 0.3) : 0
        let pulseTime = time - centreAt
        let pulse = pulseTime <= 0.22 ? Self.easeOut(pulseTime / 0.22) : 1 - Self.smooth((pulseTime - 0.22) / 0.22)
        let live = emphasis(tick, at: time)
        var result = Tick(length: 12 + max(capture * 8, pulse * 8, live * 5), blue: capture + live * (1 - capture))
        if let savedAt {
            let completion = Self.smooth((time - savedAt - Double(tick) * 0.004) / 0.45)
            result.width += (9.43 - result.width) * completion
            result.length += (14 - result.length) * completion
            result.radius -= 2 * completion
            result.opacity = 1 - completion
        }
        return result
    }

    static func still(_ tick: Int, input: Input) -> Tick {
        let captured = (input.counts[FaceEnrollmentPresentation.pose(atTick: tick)] ?? 0) >= input.samplesPerPose
        let live = input.heading.emphasis(atTick: tick)
        return Tick(length: captured ? 20 : 12 + live * 5, blue: captured ? 1 : live, opacity: input.saved ? 0 : 1)
    }

    private func emphasis(_ tick: Int, at time: TimeInterval) -> Double {
        let from = headingFrom[tick], to = input.heading.emphasis(atTick: tick)
        return from + (to - from) * Self.easeOut((time - headingAt) / 0.15)
    }

    private static func easeOut(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return 1 - pow(1 - t, 3)
    }

    private static func smooth(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }
}
