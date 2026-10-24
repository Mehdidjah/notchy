import Accelerate
import Foundation

/// Numeric helpers for descriptors. Runtime matching supplies the recognition profile's
/// dimensions, normalization and cosine distance; old records keep their original metadata.
enum FaceDescriptor {
    static let dimension = FaceRecognitionProfile.auraFace.dimension

    /// A descriptor the matcher can use: the expected length and only finite numbers.
    static func isUsable(_ descriptor: [Float], dimension: Int = dimension) -> Bool {
        descriptor.count == dimension && descriptor.allSatisfy(\.isFinite)
    }

    /// Euclidean distance, or infinity when the lengths differ or there is nothing to compare,
    /// so a malformed descriptor can never look like a match.
    static func distance(_ first: [Float], _ second: [Float]) -> Float {
        guard first.count == second.count, !first.isEmpty else { return .infinity }
        return vDSP.distanceSquared(first, second).squareRoot()
    }

    /// The element-wise mean of equally long descriptors, or `nil` when there are none or their
    /// lengths differ.
    static func mean(of descriptors: [[Float]]) -> [Float]? {
        guard let first = descriptors.first, !first.isEmpty,
              descriptors.allSatisfy({ $0.count == first.count })
        else { return nil }
        var sum = first
        for descriptor in descriptors.dropFirst() {
            sum = vDSP.add(sum, descriptor)
        }
        return vDSP.divide(sum, Float(descriptors.count))
    }
}

/// How close a face has to be to count as a match. Named presets rather than a free slider, and
/// the default is one of them, so the settings picker always shows which one is in force.
///
/// The raw distance values are retained for reading old presets and offline baseline tests.
/// Runtime comparisons always use the active recognition profile's threshold.
enum FaceMatchPreset: String, CaseIterable, Codable, Sendable {
    case strict
    case balanced
    case relaxed

    static let standard: FaceMatchPreset = .balanced

    var maximumDistance: Float {
        switch self {
        case .strict: 0.50
        case .balanced: 0.55
        case .relaxed: 0.60
        }
    }

    var title: String {
        switch self {
        case .strict: "Strict"
        case .balanced: "Balanced"
        case .relaxed: "Relaxed"
        }
    }
}

/// How one enrolled identity compares with a probe face.
struct FaceMatchScore: Equatable, Sendable {
    let identityID: UUID
    /// Distance to the identity's template, the mean of its usable samples.
    let templateDistance: Float
    /// Distance to the identity's single closest sample.
    let closestSampleDistance: Float
    /// How many samples took part (those from the current model only).
    let sampleCount: Int

    func passes(maximumDistance: Float) -> Bool {
        templateDistance <= maximumDistance && closestSampleDistance <= maximumDistance
    }
}

enum FaceMatchDecision: Equatable, Sendable {
    case matched(FaceMatchScore)
    /// No identity passed both gates; `closest` is the best-ranked one, for diagnostics.
    case notMatched(closest: FaceMatchScore)
    /// No enabled identity has samples from the current model, so there is nothing to compare.
    case nothingToCompare
    /// The probe has the wrong length or contains a non-finite number.
    case invalidProbe
}

struct FaceMatchResult: Equatable, Sendable {
    let decision: FaceMatchDecision
    /// Every comparable identity, closest template first.
    let scores: [FaceMatchScore]

    var matchedIdentityID: UUID? {
        if case .matched(let score) = decision { return score.identityID }
        return nil
    }
}

/// Decides whether a probe face belongs to one of the enrolled identities.
///
/// A match needs **both** the distance to an identity's mean template and the distance to its
/// closest single sample to be within the limit. The template alone can be pulled into range by
/// samples spread around a stranger's face; the closest sample alone can be fooled by one
/// unlucky sample. Requiring both rejects either kind of fluke.
///
/// Samples carry the identifier of the model that made them. Descriptors from different models
/// are not comparable, so samples from any other model are dropped *before* anything is ranked:
/// an identity left with none cannot be compared (it needs re-enrolment) and, crucially, can never
/// sit at the top of the ranking and block an identity that does match.
///
/// Templates are built once when the matcher is made, so a scan compares each frame against
/// ready-made vectors. The matcher is a value type and safe to use from the pipeline's actor.
struct FaceMatcher: Sendable {
    private struct Candidate: Sendable {
        let identityID: UUID
        let template: [Float]
        let samples: [[Float]]
    }

    let modelIdentifier: String
    let maximumDistance: Float
    let dimension: Int
    private let profile: FaceRecognitionProfile?
    /// Enabled identities with no usable sample from `modelIdentifier`: they need re-enrolling
    /// before Face Check can recognise them.
    let identitiesNeedingReenrolment: [UUID]
    private let candidates: [Candidate]

    init(
        identities: [FaceIdentity],
        modelIdentifier: String,
        maximumDistance: Float = FaceMatchPreset.standard.maximumDistance,
        dimension: Int = FaceDescriptor.dimension,
        profile: FaceRecognitionProfile? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.maximumDistance = maximumDistance
        self.dimension = dimension
        self.profile = profile

        var candidates: [Candidate] = []
        var stale: [UUID] = []
        for identity in identities where identity.isEnabled {
            let usable = identity.samples
                .filter { $0.modelIdentifier == modelIdentifier }
                .map(\.descriptor)
                .filter { FaceDescriptor.isUsable($0, dimension: dimension) }
            let prepared = profile.map { selected in usable.compactMap(selected.prepared) } ?? usable
            guard let mean = FaceDescriptor.mean(of: prepared),
                  let template = profile == nil ? mean : profile?.prepared(mean) else {
                stale.append(identity.id)
                continue
            }
            candidates.append(Candidate(identityID: identity.id, template: template, samples: prepared))
        }
        self.candidates = candidates
        identitiesNeedingReenrolment = stale
    }

    var hasComparableIdentities: Bool { !candidates.isEmpty }

    func match(_ probe: [Float]) -> FaceMatchResult {
        guard FaceDescriptor.isUsable(probe, dimension: dimension) else {
            return FaceMatchResult(decision: .invalidProbe, scores: [])
        }
        let scores = candidates.map { candidate in
            FaceMatchScore(
                identityID: candidate.identityID,
                templateDistance: distance(probe, candidate.template),
                closestSampleDistance: candidate.samples.map { distance(probe, $0) }.min() ?? .infinity,
                sampleCount: candidate.samples.count
            )
        }
        .sorted { ($0.templateDistance, $0.closestSampleDistance) < ($1.templateDistance, $1.closestSampleDistance) }

        guard let closest = scores.first else {
            return FaceMatchResult(decision: .nothingToCompare, scores: [])
        }
        // Everyone ranked here is enrolled on this Mac, so the closest identity that clears both
        // gates is the answer even when a closer template failed its sample gate.
        if let match = scores.first(where: { $0.passes(maximumDistance: maximumDistance) }) {
            return FaceMatchResult(decision: .matched(match), scores: scores)
        }
        return FaceMatchResult(decision: .notMatched(closest: closest), scores: scores)
    }

    init(identities: [FaceIdentity], profile: FaceRecognitionProfile, maximumDistance: Float? = nil) {
        self.init(identities: identities, modelIdentifier: profile.identifier,
                  maximumDistance: maximumDistance ?? profile.strictDistance,
                  dimension: profile.dimension, profile: profile)
    }

    private func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        profile?.distance(lhs, rhs) ?? FaceDescriptor.distance(lhs, rhs)
    }
}
