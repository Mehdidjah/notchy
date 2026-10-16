import Foundation
import Testing
@testable import Notchy

// MARK: - Helpers

private let model = "dlib-resnet-v1"
private let start = Date(timeIntervalSince1970: 1_700_000_000)

/// A made-up descriptor for one person, with a small per-view wobble.
private func person(_ seed: Float, wobble: Float = 0) -> [Float] {
    (0..<FaceDescriptor.dimension).map { index in
        let base = sin(Float(index) * 0.37 + seed) * 0.08
        return base + (index == 0 ? wobble : 0)
    }
}

private let alice = person(1)
private let stranger = person(4)

private extension FaceEnrollmentPose {
    /// A head position well inside this pose's band.
    var angles: (yaw: Double, pitch: Double) {
        switch self {
        case .centre: (0, 0)
        case .left: (-22, 0)
        case .right: (22, 0)
        case .up: (0, 18)
        case .down: (0, -18)
        case .upLeft: (-22, 18)
        case .upRight: (22, 18)
        case .downLeft: (-22, -18)
        case .downRight: (22, -18)
        }
    }
}

private func frame(
    _ pose: FaceEnrollmentPose,
    at timestamp: TimeInterval,
    yawOffset: Double = 0,
    quality: Double = 0.8,
    descriptor: [Float] = alice
) -> FaceEnrollmentFrame {
    FaceEnrollmentFrame(
        yaw: pose.angles.yaw + yawOffset,
        pitch: pose.angles.pitch,
        quality: quality,
        descriptor: descriptor,
        timestamp: timestamp
    )
}

private func makeTracker() -> FaceEnrollmentPoseTracker {
    FaceEnrollmentPoseTracker(modelIdentifier: model, startDate: start)
}

/// Feeds frames 0.25 s apart until the tracker reports something other than holding; returns
/// that event and the next free timestamp.
@discardableResult
private func holdUntilDecided(
    _ tracker: inout FaceEnrollmentPoseTracker,
    _ pose: FaceEnrollmentPose,
    from time: TimeInterval,
    yawOffset: Double = 0,
    descriptor: [Float] = alice
) -> (event: FaceEnrollmentEvent, next: TimeInterval) {
    var now = time
    for _ in 0..<20 {
        let event = tracker.process(frame(pose, at: now, yawOffset: yawOffset, descriptor: descriptor))
        now += 0.25
        if case .holding = event { continue }
        return (event, now)
    }
    return (.noFace, now)
}

// MARK: - Pose bands

struct FaceCheckPoseBandTests {
    @Test
    func everyPoseHasItsBand() {
        let bands = FaceEnrollmentPoseBands()
        for pose in FaceEnrollmentPose.allCases {
            #expect(bands.pose(yaw: pose.angles.yaw, pitch: pose.angles.pitch) == pose)
        }
        #expect(bands.pose(yaw: 8, pitch: -7) == .centre)
        #expect(bands.pose(yaw: -40, pitch: 0) == .left)
        #expect(bands.pose(yaw: 15, pitch: 30) == .upRight)
    }

    @Test
    func gapsAndExtremesBelongToNoPose() {
        let bands = FaceEnrollmentPoseBands()
        #expect(bands.pose(yaw: 11, pitch: 0) == nil)
        #expect(bands.pose(yaw: 0, pitch: -9) == nil)
        #expect(bands.pose(yaw: -45, pitch: 0) == nil)
        #expect(bands.pose(yaw: 0, pitch: 35) == nil)
        #expect(bands.pose(yaw: .nan, pitch: 0) == nil)
    }

    @Test
    func guidedOrderStartsAtTheCentreAndCoversEveryPoseOnce() {
        #expect(FaceEnrollmentPose.guidedOrder.first == .centre)
        #expect(Set(FaceEnrollmentPose.guidedOrder) == Set(FaceEnrollmentPose.allCases))
        #expect(FaceEnrollmentPose.guidedOrder.count == FaceEnrollmentPose.allCases.count)
    }
}

// MARK: - Holding a pose

struct FaceCheckEnrollmentHoldTests {
    @Test
    func aPoseIsCapturedOnlyAfterEnoughFramesAndEnoughTime() {
        var tracker = makeTracker()
        #expect(tracker.process(frame(.centre, at: 0)) == .holding(.centre, progress: 0))
        // Three frames, but only a quarter of a second.
        #expect(tracker.process(frame(.centre, at: 0.125)) == .holding(.centre, progress: 0.25))
        #expect(tracker.process(frame(.centre, at: 0.25)) == .holding(.centre, progress: 0.5))
        #expect(tracker.process(frame(.centre, at: 0.5)) == .captured(.centre, sampleNumber: 1))
        #expect(tracker.capturedCount(for: .centre) == 1)
    }

    @Test
    func timeAloneIsNotEnough() {
        var tracker = makeTracker()
        _ = tracker.process(frame(.centre, at: 0))
        #expect(tracker.process(frame(.centre, at: 0.9)) == .holding(.centre, progress: 2.0 / 3.0))
        #expect(tracker.process(frame(.centre, at: 1.0)) == .captured(.centre, sampleNumber: 1))
    }

    @Test
    func lowQualityBreaksTheHold() {
        var tracker = makeTracker()
        _ = tracker.process(frame(.centre, at: 0))
        _ = tracker.process(frame(.centre, at: 0.2))
        _ = tracker.process(frame(.centre, at: 0.4))
        #expect(tracker.process(frame(.centre, at: 0.45, quality: 0.1)) == .lowQuality)
        // The hold starts again from here.
        #expect(tracker.process(frame(.centre, at: 0.5)) == .holding(.centre, progress: 0))
        #expect(tracker.capturedSampleCount == 0)
    }

    @Test
    func leavingThePoseBreaksTheHold() {
        var tracker = makeTracker()
        _ = tracker.process(frame(.centre, at: 0))
        _ = tracker.process(frame(.centre, at: 0.2))
        #expect(tracker.process(frame(.centre, at: 0.3, yawOffset: 11)) == .betweenPoses)
        _ = tracker.process(frame(.centre, at: 0.5))
        #expect(tracker.process(frame(.centre, at: 0.75)) == .holding(.centre, progress: 0.5))
    }

    @Test
    func losingTheFaceOrTheDescriptorBreaksTheHold() {
        var tracker = makeTracker()
        _ = tracker.process(frame(.centre, at: 0))
        _ = tracker.process(frame(.centre, at: 0.3))
        #expect(tracker.noFace() == .noFace)
        #expect(tracker.process(frame(.centre, at: 0.6)) == .holding(.centre, progress: 0))
        #expect(tracker.process(frame(.centre, at: 0.7, descriptor: [1, 2])) == .unusableDescriptor)
        #expect(tracker.process(frame(.centre, at: 0.8)) == .holding(.centre, progress: 0))
    }

    @Test
    func aClockRunningBackwardsStartsTheHoldAgain() {
        var tracker = makeTracker()
        _ = tracker.process(frame(.centre, at: 5.0))
        _ = tracker.process(frame(.centre, at: 5.3))
        #expect(tracker.process(frame(.centre, at: 1.0)) == .holding(.centre, progress: 0))
    }

    @Test
    func theCentreComesFirst() {
        var tracker = makeTracker()
        #expect(tracker.process(frame(.left, at: 0)) == .centreFirst(.left))
        #expect(tracker.suggestedPose == .centre)
    }
}

// MARK: - Second samples and the same-person check

struct FaceCheckEnrollmentSampleTests {
    @Test
    func aSecondSampleOfAPoseWaitsForTimeToPass() {
        var tracker = makeTracker()
        let first = holdUntilDecided(&tracker, .centre, from: 0)
        #expect(first.event == .captured(.centre, sampleNumber: 1))
        // Held again by 1.25 s, only 0.75 s after the first capture at 0.5 s, without moving.
        #expect(tracker.process(frame(.centre, at: 0.75)) == .holding(.centre, progress: 0))
        _ = tracker.process(frame(.centre, at: 1.0))
        #expect(tracker.process(frame(.centre, at: 1.25)) == .waitingForVariation(.centre))
        #expect(tracker.process(frame(.centre, at: 1.5)) == .captured(.centre, sampleNumber: 2))
    }

    @Test
    func aSecondSampleOfAPoseCanComeSoonerWithALittleMovement() {
        var tracker = makeTracker()
        _ = holdUntilDecided(&tracker, .centre, from: 0)
        let second = holdUntilDecided(&tracker, .centre, from: 0.75, yawOffset: 4)
        #expect(second.event == .captured(.centre, sampleNumber: 2))
        #expect(tracker.samplesByPose[.centre]?.map(\.yaw) == [0, 4])
    }

    @Test
    func aDifferentFaceMidEnrolmentIsRefused() throws {
        var tracker = makeTracker()
        _ = holdUntilDecided(&tracker, .centre, from: 0)
        _ = holdUntilDecided(&tracker, .centre, from: 0.75, yawOffset: 4)
        #expect(tracker.capturedCount(for: .centre) == 2)

        let swapped = holdUntilDecided(&tracker, .left, from: 2, descriptor: stranger)
        guard case .differentFace(.left, let distance) = swapped.event else {
            Issue.record("Expected a different-face refusal, got \(swapped.event)")
            return
        }
        #expect(distance > FaceEnrollmentRules.standard.samePersonMaximumDistance)
        #expect(tracker.capturedCount(for: .left) == 0)
        #expect(tracker.differentFaceCount == 1)

        let back = holdUntilDecided(&tracker, .left, from: swapped.next, descriptor: person(1, wobble: 0.05))
        #expect(back.event == .captured(.left, sampleNumber: 1))
    }

    @Test
    func theSecondCentreSampleMustMatchTheFirst() {
        var tracker = makeTracker()
        _ = holdUntilDecided(&tracker, .centre, from: 0)
        let swapped = holdUntilDecided(&tracker, .centre, from: 2, descriptor: stranger)
        if case .differentFace(.centre, _) = swapped.event {} else {
            Issue.record("Expected a different-face refusal, got \(swapped.event)")
        }
        #expect(tracker.capturedCount(for: .centre) == 1)
    }

    @Test
    func aFinishedPoseTakesNoMoreSamples() {
        var tracker = makeTracker()
        _ = holdUntilDecided(&tracker, .centre, from: 0)
        _ = holdUntilDecided(&tracker, .centre, from: 0.75, yawOffset: 4)
        #expect(tracker.process(frame(.centre, at: 3)) == .poseAlreadyCaptured(.centre))
        #expect(tracker.suggestedPose == .left)
    }
}

// MARK: - A whole enrolment

struct FaceCheckEnrollmentRunTests {
    @Test
    func ninePosesTwiceEachCompleteTheEnrolment() throws {
        var tracker = makeTracker()
        var now: TimeInterval = 100
        for pose in FaceEnrollmentPose.guidedOrder {
            #expect(tracker.suggestedPose == pose)
            let first = holdUntilDecided(&tracker, pose, from: now, descriptor: person(1, wobble: 0.02))
            #expect(first.event == .captured(pose, sampleNumber: 1))
            let second = holdUntilDecided(&tracker, pose, from: first.next, yawOffset: 3.5, descriptor: person(1, wobble: -0.02))
            if pose == FaceEnrollmentPose.guidedOrder.last {
                #expect(second.event == .complete)
            } else {
                #expect(second.event == .captured(pose, sampleNumber: 2))
            }
            now = second.next
        }

        #expect(tracker.isComplete)
        #expect(tracker.capturedSampleCount == 18)
        #expect(tracker.requiredSampleCount == 18)
        #expect(tracker.remainingPoses.isEmpty)
        #expect(tracker.process(frame(.centre, at: now)) == .complete)

        let enrolled = try #require(tracker.makeIdentity(name: "Alice"))
        #expect(enrolled.name == "Alice")
        #expect(enrolled.isEnabled)
        #expect(enrolled.samples.count == 18)
        #expect(enrolled.samples.allSatisfy { $0.modelIdentifier == model })
        #expect(enrolled.samples.allSatisfy { $0.quality == 0.8 })
        let dates = enrolled.samples.map(\.date)
        #expect(dates == dates.sorted())
        #expect(dates.first == start.addingTimeInterval(0.5))
    }

    @Test
    func anUnfinishedEnrolmentMakesNoIdentity() {
        var tracker = makeTracker()
        _ = holdUntilDecided(&tracker, .centre, from: 0)
        #expect(tracker.makeIdentity(name: "Alice") == nil)
        #expect(tracker.centreReference == alice)
    }
}
