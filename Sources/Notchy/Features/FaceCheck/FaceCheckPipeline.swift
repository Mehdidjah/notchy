import CoreGraphics
import Foundation
import OSLog
import Vision

/// One face found in a camera frame, as plain values that can leave the pipeline.
struct FaceFrameObservation: Equatable, Sendable {
    /// Normalised to the frame, origin at the top left (the convention of capture metadata).
    var bounds: CGRect
    var landmarks: FaceLandmarkPoints
    /// Head turn and tilt in degrees; nil when Vision could not estimate them.
    var yaw: Double?
    var pitch: Double?
    /// Vision's capture quality, 0...1 (a relative score; higher is better).
    var quality: Double
}

/// What the pipeline made of one frame.
struct FaceFrameAnalysis: Sendable {
    var capturedAt: TimeInterval?
    var face: FaceFrameObservation?
    /// The aligned chip the selected model saw, for the settings page.
    var chip: CGImage?
    var descriptor: [Float]?
    var problem: String?
    var faceCount: Int = 0
    /// Deny cues remain available even if alignment or embedding failed.
    var liveness: FaceLivenessObservation?
    var pad: FacePADObservation? = nil
    var modelIdentifier: String? = nil
    /// A companion descriptor from the same enrollment frame, preserving existing in-app checks.
    var legacyDescriptor: [Float]? = nil
    /// A recoverable positioning issue. It must not carry matching or PAD evidence.
    var captureGuidance: String? = nil
}

/// Turns camera frames into face descriptors: Vision finds the face and its landmarks, the
/// aligner lines it up on the model's chip, and the embedder describes it.
///
/// Runs on its own serial queue so Vision's synchronous requests never take a thread from the
/// main actor or the shared pool; the embedder has its own queue as well.
actor FaceCheckPipeline {
    private static let logger = Logger(subsystem: "com.local.Notchy", category: "FaceCheck")
    private let queue = DispatchSerialQueue(label: "Notchy.FaceCheck.Pipeline", qos: .userInitiated)
    let embedder: FaceEmbedder
    private let enrollmentEmbedder: FaceEmbedder?
    private let legacyEnrollmentEmbedder: FaceEmbedder
    private let padModel: FacePADModel

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(embedder: FaceEmbedder, enrollmentEmbedder: FaceEmbedder? = nil, padModel: FacePADModel = FacePADModel()) {
        self.embedder = embedder
        self.enrollmentEmbedder = enrollmentEmbedder
        self.padModel = padModel
        legacyEnrollmentEmbedder = embedder.profile == .legacy ? embedder : FaceEmbedder(profile: .legacy)
    }

    func prepare(passive: Bool = false) async throws {
        try await embedder.prepare()
        if passive { try await padModel.prepare() }
    }

    func unload() async {
        await embedder.unload()
        await enrollmentEmbedder?.unload()
        await legacyEnrollmentEmbedder.unload()
        await padModel.unload()
    }

    func analyze(_ frame: CGImage, capturedAt: TimeInterval = ProcessInfo.processInfo.systemUptime,
                 generation: Int = 0, passive: Bool = false, enrolling: Bool = false) async -> FaceFrameAnalysis {
        var result = await analyzeFrame(frame, capturedAt: capturedAt, generation: generation,
                                        passive: passive || enrolling, enrolling: enrolling)
        result.capturedAt = capturedAt
        return result
    }

    private func analyzeFrame(_ frame: CGImage, capturedAt: TimeInterval, generation: Int,
                              passive: Bool, enrolling: Bool) async -> FaceFrameAnalysis {
        let embedder = enrolling ? (enrollmentEmbedder ?? embedder) : embedder
        let detection: (face: FaceFrameObservation?, count: Int, device: Bool)
        do {
            detection = try Self.detectFrame(in: frame)
        } catch {
            return FaceFrameAnalysis(problem: "Face detection failed: \(error.localizedDescription)")
        }
        guard let face = detection.face else { return FaceFrameAnalysis(faceCount: detection.count) }
        let liveness = FaceLivenessObservation(
            geometry: FaceLivenessGeometry.measure(face.landmarks) ?? .unavailable,
            yaw: face.yaw ?? .nan,
            pitch: face.pitch ?? .nan,
            quality: face.quality,
            glare: FaceLivenessImageCues.glare(in: frame, faceBounds: face.bounds) ?? .unavailable,
            enclosingDevice: detection.device,
            faceCount: detection.count
        )
        guard detection.count == 1 else {
            return FaceFrameAnalysis(face: face, faceCount: detection.count, liveness: liveness)
        }
        guard FaceCaptureFraming.contains(face.bounds) else {
            return FaceFrameAnalysis(face: face, faceCount: detection.count, liveness: liveness,
                                     captureGuidance: FaceCaptureFraming.guidance)
        }
        let chip: CGImage?
        if embedder.profile.metric == .cosine {
            chip = FaceCanonicalChip.render(frame, landmarks: face.landmarks)
        } else {
            chip = FaceChipAligner.alignment(for: face.landmarks).flatMap { FaceChipRenderer.renderImage(frame, alignment: $0) }
        }
        guard let chip else {
            return FaceFrameAnalysis(face: face, faceCount: detection.count, liveness: liveness)
        }
        var stage = "recognition"
        do {
            let descriptor = try await embedder.descriptor(for: chip)
            var legacyDescriptor: [Float]?
            if enrolling,
               let alignment = FaceChipAligner.alignment(for: face.landmarks),
               let legacyChip = FaceChipRenderer.renderImage(frame, alignment: alignment) {
                stage = "companion recognition"
                legacyDescriptor = try await legacyEnrollmentEmbedder.descriptor(for: legacyChip)
            }
            stage = "photo and screen check"
            let pad = passive ? try await padModel.evaluate(frame: frame, faceBounds: face.bounds,
                capturedAt: capturedAt, generation: generation) : nil
            return FaceFrameAnalysis(face: face, chip: chip, descriptor: descriptor,
                                     faceCount: detection.count, liveness: liveness, pad: pad,
                                     modelIdentifier: embedder.profile.identifier, legacyDescriptor: legacyDescriptor)
        } catch FaceEmbedder.Failure.modelMissing {
            return FaceFrameAnalysis(face: face, chip: chip, problem: "The face model is missing from the app.",
                                     faceCount: detection.count, liveness: liveness)
        } catch {
            let message = (error as? FaceEmbedder.Failure)?.errorDescription
                ?? (error as? FacePADModel.Failure)?.errorDescription
                ?? "The \(stage) couldn't finish. Restart the scan."
            // Fixed messages and error codes only: never log camera pixels, embeddings,
            // identity names, credentials, or an inference error's feature-value payload.
            let diagnostic = error as NSError
            Self.logger.error("Face scan failed at \(stage, privacy: .public): \(message, privacy: .public) [\(diagnostic.domain, privacy: .public):\(diagnostic.code)]")
            return FaceFrameAnalysis(face: face, chip: chip, problem: message,
                                     faceCount: detection.count, liveness: liveness)
        }
    }

    /// The largest face in the frame, with its landmarks, pose and capture quality.
    static func detectFace(in frame: CGImage) throws -> FaceFrameObservation? {
        try detectFrame(in: frame).face
    }

    private static func detectFrame(in frame: CGImage) throws -> (face: FaceFrameObservation?, count: Int, device: Bool) {
        let handler = VNImageRequestHandler(cgImage: frame, orientation: .up)
        let rectangles = VNDetectFaceRectanglesRequest()
        let devices = VNDetectRectanglesRequest()
        devices.minimumConfidence = 0.8
        devices.minimumSize = 0.15
        devices.minimumAspectRatio = 0.32
        devices.maximumAspectRatio = 0.95
        devices.maximumObservations = 8
        devices.quadratureTolerance = 20
        // Running both requests before embedding means the first matching frame cannot bypass denial.
        try handler.perform([rectangles, devices])
        guard let faces = rectangles.results, !faces.isEmpty else { return (nil, 0, false) }
        let largest = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = [largest]
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.inputFaceObservations = [largest]
        try handler.perform([landmarksRequest, qualityRequest])

        let withLandmarks = landmarksRequest.results?.first
        let regions = withLandmarks?.landmarks
        let size = CGSize(width: frame.width, height: frame.height)
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size) ?? []
        }
        let landmarks = FaceLandmarkPoints(
            leftEye: points(regions?.leftEye),
            rightEye: points(regions?.rightEye),
            nose: points(regions?.nose),
            noseCrest: points(regions?.noseCrest),
            outerLips: points(regions?.outerLips)
        ).flippedVertically(imageHeight: size.height)

        let box = largest.boundingBox
        let faceBounds = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let device = (devices.results ?? []).contains { rectangle in
            let corners = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
                .map { CGPoint(x: $0.x, y: 1 - $0.y) }
            return FaceLivenessImageCues.deviceSurroundsFace(
                faceBounds, corners: corners, confidence: Double(rectangle.confidence),
                imageAspect: Double(frame.width) / Double(frame.height)
            )
        }
        let quality = qualityRequest.results?.first?.faceCaptureQuality.map(Double.init) ?? 0
        let face = FaceFrameObservation(
            bounds: faceBounds,
            landmarks: landmarks,
            yaw: (withLandmarks?.yaw ?? largest.yaw).map { $0.doubleValue * 180 / .pi },
            pitch: (withLandmarks?.pitch ?? largest.pitch).map { $0.doubleValue * 180 / .pi },
            quality: quality
        )
        return (face, faces.count, device)
    }
}
