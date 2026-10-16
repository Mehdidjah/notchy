import Foundation
import Testing
@testable import Notchy

// MARK: - Helpers

private let currentModel = "dlib-resnet-v1"
private let oldModel = "older-model"

/// A 128-number descriptor that is zero except for the given entries.
private func descriptor(_ entries: [Int: Float] = [:]) -> [Float] {
    var values = [Float](repeating: 0, count: FaceDescriptor.dimension)
    for (index, value) in entries { values[index] = value }
    return values
}

private func sample(_ values: [Float], model: String = currentModel) -> FaceSample {
    FaceSample(
        descriptor: values,
        modelIdentifier: model,
        yaw: 0,
        pitch: 0,
        quality: 0.8,
        date: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func identity(_ name: String, enabled: Bool = true, _ samples: [FaceSample]) -> FaceIdentity {
    FaceIdentity(name: name, isEnabled: enabled, samples: samples)
}

// MARK: - Descriptor maths

struct FaceCheckDescriptorTests {
    @Test
    func distanceIsEuclidean() {
        #expect(abs(FaceDescriptor.distance(descriptor([0: 3, 1: 4]), descriptor()) - 5) < 1e-6)
        #expect(FaceDescriptor.distance(descriptor([7: 0.25]), descriptor([7: 0.25])) == 0)
        #expect(abs(FaceDescriptor.distance(descriptor([0: 1]), descriptor([1: 1])) - Float(2).squareRoot()) < 1e-6)
    }

    @Test
    func mismatchedOrEmptyDescriptorsAreInfinitelyFar() {
        #expect(FaceDescriptor.distance([1, 2, 3], [1, 2]) == .infinity)
        #expect(FaceDescriptor.distance([], []) == .infinity)
    }

    @Test
    func meanIsElementWise() throws {
        let mean = try #require(FaceDescriptor.mean(of: [descriptor([0: 1, 1: 2]), descriptor([0: 3, 2: 6])]))
        #expect(mean == descriptor([0: 2, 1: 1, 2: 3]))
        #expect(FaceDescriptor.mean(of: []) == nil)
        #expect(FaceDescriptor.mean(of: [[1, 2], [1, 2, 3]]) == nil)
    }

    @Test
    func usableDescriptorsHaveTheRightLengthAndFiniteValues() {
        #expect(FaceDescriptor.isUsable(descriptor()))
        #expect(!FaceDescriptor.isUsable([1, 2, 3]))
        #expect(!FaceDescriptor.isUsable(descriptor([5: .nan])))
        #expect(!FaceDescriptor.isUsable(descriptor([5: .infinity])))
    }
}

// MARK: - Presets

struct FaceCheckMatchPresetTests {
    @Test
    func defaultIsOneOfThePresets() {
        #expect(FaceMatchPreset.allCases.contains(FaceMatchPreset.standard))
        #expect(FaceMatchPreset.standard == .balanced)
        #expect(FaceMatcher(identities: [], modelIdentifier: currentModel).maximumDistance
            == FaceMatchPreset.standard.maximumDistance)
    }

    @Test
    func presetsRunFromStrictToRelaxed() {
        #expect(FaceMatchPreset.strict.maximumDistance == 0.50)
        #expect(FaceMatchPreset.balanced.maximumDistance == 0.55)
        #expect(FaceMatchPreset.relaxed.maximumDistance == 0.60)
        let limits = FaceMatchPreset.allCases.map(\.maximumDistance)
        #expect(limits == limits.sorted())
        #expect(Set(FaceMatchPreset.allCases.map(\.title)).count == FaceMatchPreset.allCases.count)
    }
}

// MARK: - Matching

struct FaceCheckMatcherTests {
    @Test
    func closeTemplateAndCloseSampleMatch() throws {
        let alice = identity("Alice", [sample(descriptor([0: 0.2])), sample(descriptor([0: 0.3]))])
        let matcher = FaceMatcher(identities: [alice], modelIdentifier: currentModel)
        let result = matcher.match(descriptor([0: 0.1]))
        #expect(result.matchedIdentityID == alice.id)
        let score = try #require(result.scores.first)
        #expect(abs(score.templateDistance - 0.15) < 1e-6)
        #expect(abs(score.closestSampleDistance - 0.1) < 1e-6)
        #expect(score.sampleCount == 2)
    }

    @Test
    func aCloseTemplateAloneIsNotEnough() throws {
        // Samples either side of the probe: their mean is the probe itself, but each sample is
        // 0.7 away.
        let spread = identity("Spread", [sample(descriptor([0: 0.7])), sample(descriptor([0: -0.7]))])
        let result = FaceMatcher(identities: [spread], modelIdentifier: currentModel).match(descriptor())
        let score = try #require(result.scores.first)
        #expect(score.templateDistance < 1e-6)
        #expect(abs(score.closestSampleDistance - 0.7) < 1e-6)
        #expect(result.decision == .notMatched(closest: score))
    }

    @Test
    func aCloseSampleAloneIsNotEnough() throws {
        let lucky = identity("Lucky", [
            sample(descriptor([0: 0.1])),
            sample(descriptor([1: 2])),
            sample(descriptor([2: 2]))
        ])
        let result = FaceMatcher(identities: [lucky], modelIdentifier: currentModel).match(descriptor())
        let score = try #require(result.scores.first)
        #expect(abs(score.closestSampleDistance - 0.1) < 1e-6)
        #expect(score.templateDistance > 0.9)
        #expect(result.matchedIdentityID == nil)
    }

    @Test
    func theLimitItselfStillMatches() {
        let edge = identity("Edge", [sample(descriptor([0: 0.5]))])
        let matcher = FaceMatcher(identities: [edge], modelIdentifier: currentModel, maximumDistance: 0.5)
        #expect(matcher.match(descriptor()).matchedIdentityID == edge.id)
        let stricter = FaceMatcher(identities: [edge], modelIdentifier: currentModel, maximumDistance: 0.49)
        #expect(stricter.match(descriptor()).matchedIdentityID == nil)
    }

    @Test
    func samplesFromAnotherModelAreDroppedBeforeRanking() {
        // The stale identity's old samples equal the probe exactly; if they were ranked it would
        // come first and, failing nothing, wrongly match. It must be ignored instead.
        let stale = identity("Stale", [sample(descriptor(), model: oldModel)])
        let current = identity("Current", [sample(descriptor([3: 0.3])), sample(descriptor([3: 0.2]))])
        let matcher = FaceMatcher(identities: [stale, current], modelIdentifier: currentModel)

        let result = matcher.match(descriptor())
        #expect(result.matchedIdentityID == current.id)
        #expect(result.scores.map(\.identityID) == [current.id])
        #expect(matcher.identitiesNeedingReenrolment == [stale.id])
    }

    @Test
    func onlyTheCurrentModelsSamplesOfAMixedIdentityCount() throws {
        let mixed = identity("Mixed", [
            sample(descriptor(), model: oldModel),
            sample(descriptor([4: 0.8])),
            sample(descriptor([4: 0.9]))
        ])
        let result = FaceMatcher(identities: [mixed], modelIdentifier: currentModel).match(descriptor())
        let score = try #require(result.scores.first)
        #expect(score.sampleCount == 2)
        #expect(abs(score.closestSampleDistance - 0.8) < 1e-6)
        #expect(result.matchedIdentityID == nil)
    }

    @Test
    func unusableSamplesAreIgnored() throws {
        let messy = identity("Messy", [
            sample([1, 2, 3]),
            sample(descriptor([0: .nan])),
            sample(descriptor([0: 0.1]))
        ])
        let result = FaceMatcher(identities: [messy], modelIdentifier: currentModel).match(descriptor())
        #expect(try #require(result.scores.first).sampleCount == 1)
        #expect(result.matchedIdentityID == messy.id)
    }

    @Test
    func disabledIdentitiesAreNeverMatched() {
        let off = identity("Off", enabled: false, [sample(descriptor())])
        let matcher = FaceMatcher(identities: [off], modelIdentifier: currentModel)
        #expect(matcher.match(descriptor()).decision == .nothingToCompare)
        #expect(matcher.identitiesNeedingReenrolment.isEmpty)
        #expect(!matcher.hasComparableIdentities)
    }

    @Test
    func theClosestIdentityThatClearsBothGatesWins() {
        // "Spread" has the closer template but fails its sample gate; "Near" clears both.
        let spread = identity("Spread", [sample(descriptor([0: 0.6])), sample(descriptor([0: -0.6]))])
        let near = identity("Near", [sample(descriptor([1: 0.3])), sample(descriptor([1: 0.3]))])
        let further = identity("Further", [sample(descriptor([2: 0.45])), sample(descriptor([2: 0.4]))])
        let result = FaceMatcher(identities: [further, spread, near], modelIdentifier: currentModel)
            .match(descriptor())
        #expect(result.scores.map(\.identityID) == [spread.id, near.id, further.id])
        #expect(result.matchedIdentityID == near.id)
    }

    @Test
    func nothingToCompareWithoutUsableIdentities() {
        #expect(FaceMatcher(identities: [], modelIdentifier: currentModel).match(descriptor()).decision
            == .nothingToCompare)
        let onlyStale = FaceMatcher(
            identities: [identity("Stale", [sample(descriptor(), model: oldModel)]), identity("Empty", [])],
            modelIdentifier: currentModel
        )
        #expect(onlyStale.match(descriptor()).decision == .nothingToCompare)
        #expect(onlyStale.identitiesNeedingReenrolment.count == 2)
    }

    @Test
    func malformedProbesAreRejected() {
        let matcher = FaceMatcher(
            identities: [identity("Alice", [sample(descriptor())])],
            modelIdentifier: currentModel
        )
        #expect(matcher.match([0, 0, 0]).decision == .invalidProbe)
        #expect(matcher.match(descriptor([9: .nan])).decision == .invalidProbe)
        #expect(matcher.match([]).scores.isEmpty)
    }

    @Test
    func identityKnowsWhenItNeedsReenrolment() {
        let old = identity("Old", [sample(descriptor(), model: oldModel)])
        #expect(old.needsReenrolment(forModel: currentModel))
        #expect(!old.needsReenrolment(forModel: oldModel))
        #expect(old.samples(forModel: oldModel).count == 1)
    }
}
