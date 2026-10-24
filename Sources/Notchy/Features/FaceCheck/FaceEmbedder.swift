import Accelerate
import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import OSLog

/// Turns an aligned face chip into the descriptor specified by its recognition profile.
/// Each profile owns its dimensions, preprocessing, metric, and source-weight identity.
/// This type does no detection, alignment or resizing.
/// The model loads on first use (or `prepare()`), and every load and prediction runs on the
/// actor's own serial queue, so neither the main actor nor the shared cooperative threads
/// wait on Core ML.
actor FaceEmbedder {
    enum ModelLocation: Sendable, Equatable {
        /// The profile's compiled model in the app bundle's Resources.
        case appBundle
        /// A compiled `.mlmodelc` directory.
        case compiledModel(URL)
        /// An uncompiled `.mlpackage`; compiled into a temporary directory when first loaded.
        case modelPackage(URL)
    }

    enum Failure: LocalizedError, Equatable {
        /// The model file is not where it should be; Face Check should show itself as
        /// unavailable rather than fail silently.
        case modelMissing
        case modelLoadFailed(String)
        /// The file loaded but is not the descriptor model this code was written for.
        case wrongModel(identifier: String?)
        case wrongChipSize(width: Int, height: Int)
        case unsupportedPixelFormat(OSType)
        case pixelBufferUnavailable
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .modelMissing, .wrongModel:
                "The face model is unavailable. Reopen Notchy and retry."
            case .modelLoadFailed:
                "Face recognition couldn't start. Reopen Notchy and retry."
            case .wrongChipSize:
                "Face alignment failed. Restart the scan."
            case .unsupportedPixelFormat, .pixelBufferUnavailable:
                "The camera image couldn't be prepared. Restart the scan."
            case .unexpectedOutput:
                "Face recognition returned an invalid result. Restart the scan."
            }
        }
    }

    /// Stored next to every saved descriptor, so descriptors from another model are never
    /// compared with this one's.
    static let modelIdentifier = FaceRecognitionProfile.auraFace.identifier
    static let bundledModelName = FaceRecognitionProfile.auraFace.modelName

    private static let inputName = "image"
    private static let outputName = "descriptor"
    private static let identifierMetadataKey = "notchy.faceModel.identifier"
    private static let logger = Logger(subsystem: "com.local.Notchy", category: "FaceCheck")

    private let location: ModelLocation
    nonisolated let profile: FaceRecognitionProfile
    private let computeUnits: MLComputeUnits
    private let queue: DispatchSerialQueue
    private var model: MLModel?
    private var compileTask: Task<URL, any Error>?
    private var temporaryCompiledURL: URL?
    private var loadGeneration = 0

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// `computeUnits` defaults to CPU and Neural Engine so the GPU stays free for the island.
    init(location: ModelLocation = .appBundle, computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
         profile: FaceRecognitionProfile = .auraFace) {
        self.location = location
        self.profile = profile
        self.computeUnits = computeUnits
        self.queue = DispatchSerialQueue(label: "com.local.Notchy.FaceEmbedder", qos: .userInitiated)
    }

    deinit {
        if let temporaryCompiledURL {
            try? FileManager.default.removeItem(at: temporaryCompiledURL)
        }
    }

    /// The compiled model inside the running app, or nil when this build has none.
    nonisolated static var bundledModelURL: URL? {
        Bundle.main.url(forResource: bundledModelName, withExtension: "mlmodelc")
    }

    var isLoaded: Bool { model != nil }

    /// Loads the model ahead of the first scan. Calling it again does nothing.
    func prepare() async throws {
        _ = try await loadedModel()
    }

    /// Drops the model (and any temporary compiled copy) to give the memory back.
    func unload() {
        loadGeneration &+= 1
        compileTask?.cancel()
        compileTask = nil
        model = nil
        if let temporaryCompiledURL {
            try? FileManager.default.removeItem(at: temporaryCompiledURL)
            self.temporaryCompiledURL = nil
        }
    }

    /// Descriptor for a profile-sized chip. RGB images are read in their own colour space, so the
    /// pixel values reach the model unchanged.
    func descriptor(for chip: CGImage) async throws -> [Float] {
        guard chip.width == profile.chipSize, chip.height == profile.chipSize else {
            throw Failure.wrongChipSize(width: chip.width, height: chip.height)
        }
        let buffer = try Self.makePixelBuffer(from: chip)
        let model = try await loadedModel()
        return try predict(with: model, chip: buffer)
    }

    /// Descriptor for a profile-sized chip in a 32BGRA or 32ARGB pixel buffer.
    func descriptor(for chip: CVPixelBuffer) async throws -> [Float] {
        let width = CVPixelBufferGetWidth(chip)
        let height = CVPixelBufferGetHeight(chip)
        guard width == profile.chipSize, height == profile.chipSize else {
            throw Failure.wrongChipSize(width: width, height: height)
        }
        let format = CVPixelBufferGetPixelFormatType(chip)
        guard format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB else {
            throw Failure.unsupportedPixelFormat(format)
        }
        let model = try await loadedModel()
        return try predict(with: model, chip: chip)
    }

    /// Euclidean distance, the measure the network was trained with.
    nonisolated static func distance(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "descriptors must have the same length")
        return vDSP.distanceSquared(a, b).squareRoot()
    }

    // MARK: - Loading

    private func loadedModel() async throws -> MLModel {
        if let model { return model }
        let generation = loadGeneration
        let compiledURL = try await compiledModelURL()
        guard generation == loadGeneration, !Task.isCancelled else { throw CancellationError() }
        // Another call may have finished loading while this one waited for the compiler.
        if let model { return model }

        let started = ContinuousClock.now
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let loaded: MLModel
        do {
            loaded = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } catch {
            Self.logger.error("Face model failed to load: \(error.localizedDescription, privacy: .public)")
            throw Failure.modelLoadFailed(error.localizedDescription)
        }
        let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        let identifier = metadata?[Self.identifierMetadataKey]
        guard identifier == profile.identifier,
              metadata?["notchy.faceModel.sourceSHA256"] == profile.sourceSHA256 else {
            throw Failure.wrongModel(identifier: identifier)
        }
        if profile.metric == .cosine {
            guard metadata?["notchy.faceModel.precision"] == profile.precision,
                  metadata?["notchy.faceModel.alignment"] == profile.alignmentIdentifier,
                  metadata?["notchy.faceModel.sourceRevision"] == profile.sourceRevision,
                  metadata?["notchy.faceModel.inputNormalization"] == profile.inputNormalization,
                  metadata?["notchy.faceModel.outputNormalization"] == profile.outputNormalization,
                  metadata?["notchy.faceModel.descriptorLength"] == String(profile.dimension) else {
                throw Failure.wrongModel(identifier: identifier)
            }
        }
        model = loaded
        let elapsed = ContinuousClock.now - started
        Self.logger.info("Face model loaded in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        return loaded
    }

    private func compiledModelURL() async throws -> URL {
        switch location {
        case .appBundle:
            guard let url = Bundle.main.url(forResource: profile.modelName, withExtension: "mlmodelc") else {
                Self.logger.error("A required face model is missing from the app bundle")
                throw Failure.modelMissing
            }
            return url
        case .compiledModel(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.modelMissing }
            return url
        case .modelPackage(let url):
            if let temporaryCompiledURL { return temporaryCompiledURL }
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.modelMissing }
            let task = compileTask ?? Task { try await MLModel.compileModel(at: url) }
            let generation = loadGeneration
            compileTask = task
            defer { if generation == loadGeneration { compileTask = nil } }
            do {
                let compiled = try await task.value
                guard generation == loadGeneration, !Task.isCancelled else {
                    if temporaryCompiledURL != compiled { try? FileManager.default.removeItem(at: compiled) }
                    throw CancellationError()
                }
                temporaryCompiledURL = compiled
                return compiled
            } catch {
                throw Failure.modelLoadFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Prediction

    private func predict(with model: MLModel, chip: CVPixelBuffer) throws -> [Float] {
        let input = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: MLFeatureValue(pixelBuffer: chip)])
        let output = try model.prediction(from: input)
        guard let values = output.featureValue(for: Self.outputName)?.multiArrayValue,
              let descriptor = profile.prepared(Self.floats(from: values))
        else { throw Failure.unexpectedOutput }
        return descriptor
    }

    /// Reads a descriptor output, honouring its strides.
    static func floats(from array: MLMultiArray) -> [Float] {
        let count = array.count
        let step = array.strides.last?.intValue ?? 1
        if array.dataType == .float32 {
            return array.withUnsafeBufferPointer(ofType: Float.self) { storage in
                (0..<count).map { storage[$0 * step] }
            }
        }
        let leading = Array(repeating: NSNumber(value: 0), count: max(array.shape.count - 1, 0))
        return (0..<count).map { array[leading + [NSNumber(value: $0)]].floatValue }
    }

    /// Copies a square image into a new 32BGRA buffer without changing its pixel values:
    /// the context uses the image's own RGB colour space and a plain copy, so no colour
    /// matching or blending happens. Transparent pixels become black.
    static func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        let side = image.width
        guard image.height == side, side > 0 else { throw Failure.wrongChipSize(width: side, height: image.height) }
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
        ]
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &created
        )
        guard status == kCVReturnSuccess, let buffer = created else { throw Failure.pixelBufferUnavailable }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var spaces: [CGColorSpace] = []
        if let own = image.colorSpace, own.model == .rgb { spaces.append(own) }
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB) { spaces.append(sRGB) }
        for space in spaces {
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: space, bitmapInfo: bitmapInfo
            ) else { continue }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return buffer
        }
        throw Failure.pixelBufferUnavailable
    }
}
