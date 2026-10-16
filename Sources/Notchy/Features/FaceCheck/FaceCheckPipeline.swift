import CoreGraphics
import Foundation
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
    var face: FaceFrameObservation?
    /// The 150×150 chip the model saw, for the settings page.
    var chip: CGImage?
    var descriptor: [Float]?
    var problem: String?
}

/// Turns camera frames into face descriptors: Vision finds the face and its landmarks, the
/// aligner lines it up on the model's chip, and the embedder describes it.
///
/// Runs on its own serial queue so Vision's synchronous requests never take a thread from the
/// main actor or the shared pool; the embedder has its own queue as well.
actor FaceCheckPipeline {
    private let queue = DispatchSerialQueue(label: "Notchy.FaceCheck.Pipeline", qos: .userInitiated)
    let embedder: FaceEmbedder

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(embedder: FaceEmbedder) {
        self.embedder = embedder
    }

    func analyze(_ frame: CGImage) async -> FaceFrameAnalysis {
        let face: FaceFrameObservation?
        do {
            face = try Self.detectFace(in: frame)
        } catch {
            return FaceFrameAnalysis(problem: "Face detection failed: \(error.localizedDescription)")
        }
        guard let face else { return FaceFrameAnalysis() }
        guard let alignment = FaceChipAligner.alignment(for: face.landmarks),
              let chip = FaceChipRenderer.renderImage(frame, alignment: alignment)
        else {
            return FaceFrameAnalysis(face: face)
        }
        do {
            let descriptor = try await embedder.descriptor(for: chip)
            return FaceFrameAnalysis(face: face, chip: chip, descriptor: descriptor)
        } catch FaceEmbedder.Failure.modelMissing {
            return FaceFrameAnalysis(face: face, chip: chip, problem: "The face model is missing from the app.")
        } catch {
            return FaceFrameAnalysis(face: face, chip: chip, problem: "The face model failed: \(error.localizedDescription)")
        }
    }

    /// The largest face in the frame, with its landmarks, pose and capture quality.
    static func detectFace(in frame: CGImage) throws -> FaceFrameObservation? {
        let handler = VNImageRequestHandler(cgImage: frame, orientation: .up)
        let rectangles = VNDetectFaceRectanglesRequest()
        try handler.perform([rectangles])
        guard let faces = rectangles.results, !faces.isEmpty else { return nil }
        let largest = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = [largest]
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.inputFaceObservations = [largest]
        try handler.perform([landmarksRequest, qualityRequest])

        guard let withLandmarks = landmarksRequest.results?.first, let regions = withLandmarks.landmarks else {
            return nil
        }
        let size = CGSize(width: frame.width, height: frame.height)
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size) ?? []
        }
        let landmarks = FaceLandmarkPoints(
            leftEye: points(regions.leftEye),
            rightEye: points(regions.rightEye),
            nose: points(regions.nose),
            noseCrest: points(regions.noseCrest),
            outerLips: points(regions.outerLips)
        ).flippedVertically(imageHeight: size.height)

        let box = largest.boundingBox
        let quality = qualityRequest.results?.first?.faceCaptureQuality.map(Double.init) ?? 0
        return FaceFrameObservation(
            bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
            landmarks: landmarks,
            yaw: largest.yaw.map { $0.doubleValue * 180 / .pi },
            pitch: largest.pitch.map { $0.doubleValue * 180 / .pi },
            quality: quality
        )
    }
}
