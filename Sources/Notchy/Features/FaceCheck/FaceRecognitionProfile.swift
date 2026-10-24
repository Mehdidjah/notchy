import Foundation

/// The complete descriptor contract. Changing any preprocessing step requires a new ID and enrollment.
struct FaceRecognitionProfile: Equatable, Sendable {
    enum Metric: String, Sendable { case euclidean, cosine }
    let identifier: String
    let modelName: String
    let sourceSHA256: String
    let chipSize: Int
    let dimension: Int
    let metric: Metric
    let strictDistance: Float
    let enrollmentDistance: Float

    var schemaVersion: Int { 1 }
    var alignmentIdentifier: String { metric == .cosine ? "five-point-112-v1" : "dlib-five-point-150-padding-0.25-v1" }
    var inputNormalization: String { metric == .cosine ? "(RGB - 127.5) / 127.5" : "(RGB - [122.782, 117.001, 104.298]) / 256" }
    var outputNormalization: String { metric == .cosine ? "L2; cosine similarity" : "none; Euclidean distance" }
    var precision: String { metric == .cosine ? "fp32" : "fp16" }
    var sourceRevision: String? { metric == .cosine ? "af6d057c9b0ec4071d4c49c80e3539258798b609" : nil }

    /// These evaluation defaults are also used by explicitly selected personal testing builds.
    /// Automatic Mac unlocking in normal builds needs a passing validation report with a frozen threshold.
    static let auraFace = FaceRecognitionProfile(
        identifier: "auraface-v1-r1", modelName: "AuraFace",
        sourceSHA256: "a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60",
        chipSize: 112, dimension: 512, metric: .cosine, strictDistance: 0.4, enrollmentDistance: 0.5)

    func prepared(_ values: [Float]) -> [Float]? {
        guard values.count == dimension, values.allSatisfy(\.isFinite) else { return nil }
        guard metric == .cosine else { return values }
        let norm = sqrt(values.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm.isFinite, norm > 1e-12 else { return nil }
        return values.map { Float(Double($0) / norm) }
    }

    func distance(_ first: [Float], _ second: [Float]) -> Float {
        guard let first = prepared(first), let second = prepared(second) else { return .infinity }
        if metric == .euclidean { return FaceDescriptor.distance(first, second) }
        let dot = zip(first, second).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        return Float(max(0, min(2, 1 - dot)))
    }

    func maximumDistance(for preset: FaceMatchPreset) -> Float {
        metric == .euclidean ? preset.maximumDistance : strictDistance
    }

    func withStrictDistance(_ distance: Float) -> Self {
        Self(identifier: identifier, modelName: modelName, sourceSHA256: sourceSHA256,
             chipSize: chipSize, dimension: dimension, metric: metric,
             strictDistance: distance, enrollmentDistance: min(enrollmentDistance, distance))
    }
}
