import Foundation

// MARK: - Stored values

/// One enrolled view of a face: its descriptor plus how it was captured.
///
/// The pose and quality are kept so a later recapture can target weak poses, and the model
/// identifier because descriptors from different models cannot be compared (see `FaceMatcher`).
/// Only these numbers are stored, never a picture.
struct FaceSample: Codable, Equatable, Sendable {
    var descriptor: [Float]
    var modelIdentifier: String
    /// Degrees; positive when the face turns towards the right edge of the image.
    var yaw: Double
    /// Degrees; positive when the face tilts up.
    var pitch: Double
    /// Vision's face capture quality, 0...1.
    var quality: Double
    var date: Date
}

/// A person Face Check recognises.
struct FaceIdentity: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// A disabled identity stays stored but is never matched.
    var isEnabled: Bool
    var samples: [FaceSample]

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, samples: [FaceSample] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.samples = samples
    }

    func samples(forModel modelIdentifier: String) -> [FaceSample] {
        samples.filter { $0.modelIdentifier == modelIdentifier }
    }

    /// True when none of the samples came from `modelIdentifier`, so the face has to be enrolled
    /// again before the current model can recognise it.
    func needsReenrolment(forModel modelIdentifier: String) -> Bool {
        samples(forModel: modelIdentifier).isEmpty
    }
}

// MARK: - Poses

/// The nine head positions enrolment asks for. Directions are as seen in the image: `left` means
/// the face turns towards the left edge of the picture.
enum FaceEnrollmentPose: String, CaseIterable, Codable, Sendable {
    case centre
    case left
    case right
    case up
    case down
    case upLeft
    case upRight
    case downLeft
    case downRight

    /// The centre first, because later samples are checked against it, then once around the
    /// circle so the guide never asks for a jump across the face.
    static let guidedOrder: [FaceEnrollmentPose] = [
        .centre, .left, .upLeft, .up, .upRight, .right, .downRight, .down, .downLeft
    ]
}

/// Yaw and pitch bands that sort a head position into one of the nine poses.
///
/// Each axis has a centred band and a turned band with a gap between them. A face in the gap is
/// in no pose at all, so a head drifting across a boundary cannot flicker between two poses and
/// a sample is never filed under the wrong one. Beyond the turned band the face is too far round
/// for a useful descriptor. Angles are in degrees; tune them against real webcam captures.
struct FaceEnrollmentPoseBands: Equatable, Sendable {
    var centredYaw: Double = 8
    var centredPitch: Double = 7
    var turnedYaw: ClosedRange<Double> = 15...40
    var turnedPitch: ClosedRange<Double> = 12...30

    func pose(yaw: Double, pitch: Double) -> FaceEnrollmentPose? {
        guard let horizontal = Self.zone(yaw, centred: centredYaw, turned: turnedYaw),
              let vertical = Self.zone(pitch, centred: centredPitch, turned: turnedPitch)
        else { return nil }
        switch (horizontal, vertical) {
        case (.negative, .negative): return .downLeft
        case (.negative, .centred): return .left
        case (.negative, .positive): return .upLeft
        case (.centred, .negative): return .down
        case (.centred, .centred): return .centre
        case (.centred, .positive): return .up
        case (.positive, .negative): return .downRight
        case (.positive, .centred): return .right
        case (.positive, .positive): return .upRight
        }
    }

    private enum Zone {
        case negative
        case centred
        case positive
    }

    private static func zone(_ angle: Double, centred: Double, turned: ClosedRange<Double>) -> Zone? {
        guard angle.isFinite else { return nil }
        if abs(angle) <= centred { return .centred }
        if turned.contains(abs(angle)) { return angle > 0 ? .positive : .negative }
        return nil
    }
}

/// The gates a frame must pass before enrolment keeps it.
struct FaceEnrollmentRules: Equatable, Sendable {
    var bands = FaceEnrollmentPoseBands()
    /// A pose must be held for this many consecutive usable frames...
    var holdFrames = 3
    /// ...and for at least this long, so a head sweeping through a band is not captured.
    var holdDuration: TimeInterval = 0.5
    /// Vision's face capture quality below which a frame is ignored (blur, poor light, occlusion).
    var minimumQuality = 0.3
    var samplesPerPose = 2
    /// A further sample of the same pose needs this much time since the previous one...
    var repeatSampleSpacing: TimeInterval = 1.0
    /// ...or this much head movement (degrees of yaw or pitch), so the two are not near-copies.
    var repeatSamplePoseChange = 3.0
    /// A sample further than this from the centre-pose samples is treated as someone else.
    /// dlib's same-person distance, looser than the matching presets because turned poses sit
    /// further from the centre ones than a second centre view would.
    var samePersonMaximumDistance: Float = 0.6
    var descriptorDimension = FaceDescriptor.dimension

    static let standard = FaceEnrollmentRules()
}

// MARK: - Tracker

/// One processed camera frame during enrolment.
struct FaceEnrollmentFrame: Equatable, Sendable {
    /// Degrees; positive when the face turns towards the right edge of the image. The Vision
    /// adapter converts Vision's radians and applies any mirroring.
    var yaw: Double
    /// Degrees; positive when the face tilts up.
    var pitch: Double
    /// Vision's face capture quality, 0...1.
    var quality: Double
    var descriptor: [Float]
    /// Seconds on a clock that only moves forward (a capture timestamp, not the wall clock).
    var timestamp: TimeInterval
}

/// What the tracker made of the latest frame, for the guide to show.
enum FaceEnrollmentEvent: Equatable, Sendable {
    /// No face in the frame.
    case noFace
    /// The descriptor has the wrong length or a non-finite number.
    case unusableDescriptor
    /// The head is between poses or turned too far.
    case betweenPoses
    case lowQuality
    /// A turned pose while the centre still needs samples; the centre comes first.
    case centreFirst(FaceEnrollmentPose)
    /// This pose already has all its samples.
    case poseAlreadyCaptured(FaceEnrollmentPose)
    /// Holding a pose; `progress` runs 0...1 towards a capture.
    case holding(FaceEnrollmentPose, progress: Double)
    /// Held long enough, but too soon after this pose's previous sample with too little movement.
    case waitingForVariation(FaceEnrollmentPose)
    /// The face does not match the centre-pose samples; nothing was kept.
    case differentFace(FaceEnrollmentPose, distance: Float)
    case captured(FaceEnrollmentPose, sampleNumber: Int)
    /// Every pose has all its samples.
    case complete
}

/// The enrolment state machine: feed it every processed frame and it decides when a pose has been
/// held well enough to keep a sample.
///
/// Rules, in order:
/// 1. The frame must carry a usable descriptor, sit inside one pose's band and meet the quality
///    floor; any frame that does not breaks the current hold.
/// 2. The centre pose is collected first, because it is the reference for rule 5.
/// 3. A pose is captured after `holdFrames` consecutive frames in it spanning `holdDuration`.
///    Each capture ends the hold, so every sample needs a hold of its own.
/// 4. A pose's second sample needs either time or a little movement since its first, so the two
///    describe different moments rather than one frame twice.
/// 5. Every sample after the first is compared with the centre-pose samples; a face that is too
///    far away is someone else stepping in, and the sample is refused.
///
/// A pure value type with no clock and no camera, so every rule is testable with synthetic frames.
struct FaceEnrollmentPoseTracker: Sendable {
    private struct Hold: Sendable {
        let pose: FaceEnrollmentPose
        let startedAt: TimeInterval
        var frameCount: Int
    }

    let rules: FaceEnrollmentRules
    let modelIdentifier: String
    /// Wall-clock time of the first frame; sample dates are this plus capture-clock time.
    let startDate: Date

    private(set) var samplesByPose: [FaceEnrollmentPose: [FaceSample]] = [:]
    /// How many samples were refused as a different face, so the guide can say someone else is in
    /// view after a few.
    private(set) var differentFaceCount = 0
    private var sampleTimestamps: [FaceEnrollmentPose: [TimeInterval]] = [:]
    private var hold: Hold?
    private var firstTimestamp: TimeInterval?
    private var lastTimestamp: TimeInterval?

    init(modelIdentifier: String, startDate: Date = Date(), rules: FaceEnrollmentRules = .standard) {
        self.modelIdentifier = modelIdentifier
        self.startDate = startDate
        self.rules = rules
    }

    // MARK: Progress

    var requiredSampleCount: Int { FaceEnrollmentPose.allCases.count * rules.samplesPerPose }
    var capturedSampleCount: Int { samplesByPose.values.reduce(0) { $0 + $1.count } }
    var isComplete: Bool { capturedSampleCount >= requiredSampleCount }

    func capturedCount(for pose: FaceEnrollmentPose) -> Int {
        samplesByPose[pose]?.count ?? 0
    }

    /// Poses still short of samples, in guided order.
    var remainingPoses: [FaceEnrollmentPose] {
        FaceEnrollmentPose.guidedOrder.filter { capturedCount(for: $0) < rules.samplesPerPose }
    }

    /// The pose the guide should ask for next.
    var suggestedPose: FaceEnrollmentPose? { remainingPoses.first }

    /// All samples kept so far, in guided order.
    var samples: [FaceSample] {
        FaceEnrollmentPose.guidedOrder.flatMap { samplesByPose[$0] ?? [] }
    }

    /// The mean of the centre-pose samples, which later samples must stay close to.
    var centreReference: [Float]? {
        FaceDescriptor.mean(of: (samplesByPose[.centre] ?? []).map(\.descriptor))
    }

    /// A new identity holding every sample, once enrolment is complete.
    func makeIdentity(name: String, id: UUID = UUID()) -> FaceIdentity? {
        guard isComplete else { return nil }
        return FaceIdentity(id: id, name: name, isEnabled: true, samples: samples)
    }

    // MARK: Frames

    /// The face left the frame: any hold in progress is broken.
    mutating func noFace() -> FaceEnrollmentEvent {
        hold = nil
        return isComplete ? .complete : .noFace
    }

    mutating func process(_ frame: FaceEnrollmentFrame) -> FaceEnrollmentEvent {
        guard !isComplete else { return .complete }

        // A clock that runs backwards means a new capture session; start the hold afresh.
        if let lastTimestamp, frame.timestamp < lastTimestamp { hold = nil }
        lastTimestamp = frame.timestamp
        if firstTimestamp == nil { firstTimestamp = frame.timestamp }

        guard FaceDescriptor.isUsable(frame.descriptor, dimension: rules.descriptorDimension) else {
            hold = nil
            return .unusableDescriptor
        }
        guard let pose = rules.bands.pose(yaw: frame.yaw, pitch: frame.pitch) else {
            hold = nil
            return .betweenPoses
        }
        guard frame.quality.isFinite, frame.quality >= rules.minimumQuality else {
            hold = nil
            return .lowQuality
        }
        if pose != .centre, capturedCount(for: .centre) < rules.samplesPerPose {
            hold = nil
            return .centreFirst(pose)
        }
        guard capturedCount(for: pose) < rules.samplesPerPose else {
            hold = nil
            return .poseAlreadyCaptured(pose)
        }

        var current = hold.flatMap { $0.pose == pose ? $0 : nil }
            ?? Hold(pose: pose, startedAt: frame.timestamp, frameCount: 0)
        current.frameCount += 1
        hold = current

        let elapsed = frame.timestamp - current.startedAt
        guard current.frameCount >= rules.holdFrames, elapsed >= rules.holdDuration else {
            let frameShare = Double(current.frameCount) / Double(max(1, rules.holdFrames))
            let timeShare = rules.holdDuration > 0 ? elapsed / rules.holdDuration : 1
            return .holding(pose, progress: min(1, frameShare, timeShare))
        }

        if let previous = samplesByPose[pose]?.last, let previousTime = sampleTimestamps[pose]?.last {
            let spaced = frame.timestamp - previousTime >= rules.repeatSampleSpacing
            let moved = max(abs(frame.yaw - previous.yaw), abs(frame.pitch - previous.pitch))
                >= rules.repeatSamplePoseChange
            // Keep holding: once enough time has passed the next frame qualifies.
            guard spaced || moved else { return .waitingForVariation(pose) }
        }

        if let reference = centreReference {
            let distance = FaceDescriptor.distance(frame.descriptor, reference)
            guard distance <= rules.samePersonMaximumDistance else {
                hold = nil
                differentFaceCount += 1
                return .differentFace(pose, distance: distance)
            }
        }

        let sample = FaceSample(
            descriptor: frame.descriptor,
            modelIdentifier: modelIdentifier,
            yaw: frame.yaw,
            pitch: frame.pitch,
            quality: frame.quality,
            date: startDate.addingTimeInterval(frame.timestamp - (firstTimestamp ?? frame.timestamp))
        )
        samplesByPose[pose, default: []].append(sample)
        sampleTimestamps[pose, default: []].append(frame.timestamp)
        hold = nil
        return isComplete ? .complete : .captured(pose, sampleNumber: capturedCount(for: pose))
    }
}
