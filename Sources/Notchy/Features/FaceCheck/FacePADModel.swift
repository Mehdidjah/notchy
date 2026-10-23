import CoreGraphics
import CoreML
import Foundation

/// The two small, independent RGB presentation-attack models run locally on a dedicated queue.
/// They classify contextual crops; the face-recognition chip is not a suitable input here.
actor FacePADModel {
    enum Location: Equatable, Sendable {
        case appBundle
        case compiledModels(URL)
        case modelPackages(URL)
    }

    enum Failure: LocalizedError, Equatable {
        case modelMissing(String)
        case modelLoadFailed(String)
        case wrongModel(String)
        case invalidFrame
        case invalidBounds
        case invalidProvenance
        case unexpectedOutput
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelMissing, .wrongModel:
                "Photo and screen detection is unavailable. Reopen Notchy and retry."
            case .modelLoadFailed:
                "Photo and screen detection couldn't start. Reopen Notchy and retry."
            case .invalidFrame:
                "The live-face check couldn't read the camera image. Restart the scan."
            case .invalidBounds:
                "Keep your whole face inside the circle, then retry."
            case .invalidProvenance, .cancelled:
                "The camera was interrupted. Restart the scan."
            case .unexpectedOutput:
                "The live-face check returned an invalid result. Restart the scan."
            }
        }
    }

    enum Variant: String, CaseIterable, Sendable {
        case v2 = "MiniFASNetV2"
        case v1SE = "MiniFASNetV1SE"
        var cropScale: Double { self == .v2 ? 2.7 : 4 }
        var sourceSHA256: String {
            switch self {
            case .v2: "a5eb02e1843f19b5386b953cc4c9f011c3f985d0ee2bb9819eea9a142099bec0"
            case .v1SE: "84ee1d37d96894d5e82de5a57df044ef80a58be2b218b5ed7cdfd875ec2f5990"
            }
        }
    }

    static let modelIdentifier = FacePADObservation.modelIdentifier
    static let inputSize = 80
    static let inputName = "image"
    static let outputName = "logits"
    static var bundledModelNames: [String] { Variant.allCases.map(\.rawValue) }

    private let location: Location
    private let computeUnits: MLComputeUnits
    private let queue = DispatchSerialQueue(label: "Notchy.FacePAD", qos: .userInitiated)
    private var models: [Variant: MLModel] = [:]
    private var compileTasks: [Variant: Task<URL, any Error>] = [:]
    private var temporaryURLs: [Variant: URL] = [:]
    private var loadGeneration = 0

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(location: Location = .appBundle, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) {
        self.location = location
        self.computeUnits = computeUnits
    }

    deinit {
        for url in temporaryURLs.values { try? FileManager.default.removeItem(at: url) }
    }

    var isLoaded: Bool { models.count == Variant.allCases.count }

    func prepare() async throws {
        let lifetime = loadGeneration
        for variant in Variant.allCases {
            _ = try await loadedModel(variant)
            guard lifetime == loadGeneration else { throw Failure.cancelled }
        }
    }

    /// Stops retaining loaded weights and temporary compiled packages. An in-flight compile
    /// cannot repopulate the cache after the feature has been turned off.
    func unload() {
        loadGeneration &+= 1
        models.removeAll()
        for task in compileTasks.values { task.cancel() }
        compileTasks.removeAll()
        for url in temporaryURLs.values { try? FileManager.default.removeItem(at: url) }
        temporaryURLs.removeAll()
    }

    func evaluate(frame: CGImage, faceBounds: CGRect, capturedAt: TimeInterval, generation: Int) async throws -> FacePADObservation {
        guard capturedAt.isFinite, capturedAt >= 0 else { throw Failure.invalidProvenance }
        let lifetime = loadGeneration
        let image = try FacePADImage(frame)
        var scores: [Variant: [Float]] = [:]
        for variant in Variant.allCases {
            let pixels = try image.bgrTensor(faceBounds: faceBounds, scale: variant.cropScale)
            scores[variant] = try await probabilities(tensor: pixels, variant: variant)
            guard lifetime == loadGeneration else { throw Failure.cancelled }
        }
        return FacePADObservation(capturedAt: capturedAt, generation: generation,
                                  miniFASNetV2: scores[.v2]!, miniFASNetV1SE: scores[.v1SE]!)
    }

    /// Exposed to conversion-parity tests: a contiguous 1×3×80×80 BGR float tensor, 0...255.
    func probabilities(tensor: [Float], variant: Variant) async throws -> [Float] {
        guard tensor.count == 3 * Self.inputSize * Self.inputSize,
              tensor.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else { throw Failure.invalidFrame }
        let lifetime = loadGeneration
        let model = try await loadedModel(variant)
        guard lifetime == loadGeneration else { throw Failure.cancelled }
        return try Self.predict(model, tensor: tensor)
    }

    private static func predict(_ model: MLModel, tensor: [Float]) throws -> [Float] {
        let array = try MLMultiArray(shape: [1, 3, 80, 80], dataType: .float32)
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { storage, _ in
            for index in tensor.indices { storage[index] = tensor[index] }
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: MLFeatureValue(multiArray: array)])
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: Self.outputName)?.multiArrayValue,
              logits.count == 3, logits.shape.last?.intValue == 3,
              logits.shape.dropLast().allSatisfy({ $0.intValue == 1 }) else {
            throw Failure.unexpectedOutput
        }
        let leading = Array(repeating: NSNumber(value: 0), count: max(0, logits.shape.count - 1))
        let values = (0..<3).map { logits[leading + [NSNumber(value: $0)]].floatValue }
        guard let probabilities = Self.softmax(values) else { throw Failure.unexpectedOutput }
        return probabilities
    }

    nonisolated static func softmax(_ logits: [Float]) -> [Float]? {
        guard logits.count == 3, logits.allSatisfy(\.isFinite), let maximum = logits.max() else { return nil }
        let exponentials = logits.map { exp(Double($0 - maximum)) }
        let sum = exponentials.reduce(0, +)
        guard sum.isFinite, sum > 0 else { return nil }
        return exponentials.map { Float($0 / sum) }
    }

    private func loadedModel(_ variant: Variant) async throws -> MLModel {
        if let model = models[variant] { return model }
        let lifetime = loadGeneration
        let url = try await compiledURL(variant)
        guard lifetime == loadGeneration else { throw Failure.cancelled }
        if let model = models[variant] { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let loaded: MLModel
        do { loaded = try MLModel(contentsOf: url, configuration: configuration) }
        catch { throw Failure.modelLoadFailed(error.localizedDescription) }
        let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard metadata?["notchy.pad.identifier"] == Self.modelIdentifier,
              metadata?["notchy.pad.variant"] == variant.rawValue,
              metadata?["notchy.pad.sourceSHA256"] == variant.sourceSHA256,
              let input = loaded.modelDescription.inputDescriptionsByName[Self.inputName]?.multiArrayConstraint,
              input.shape.map(\.intValue) == [1, 3, 80, 80], input.dataType == .float32,
              let output = loaded.modelDescription.outputDescriptionsByName[Self.outputName]?.multiArrayConstraint,
              output.shape.map(\.intValue) == [1, 3] else {
            throw Failure.wrongModel(variant.rawValue)
        }
        models[variant] = loaded
        return loaded
    }

    private func compiledURL(_ variant: Variant) async throws -> URL {
        switch location {
        case .appBundle:
            guard let url = Bundle.main.url(forResource: variant.rawValue, withExtension: "mlmodelc") else {
                throw Failure.modelMissing(variant.rawValue)
            }
            return url
        case .compiledModels(let directory):
            let url = directory.appendingPathComponent(variant.rawValue + ".mlmodelc")
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.modelMissing(variant.rawValue) }
            return url
        case .modelPackages(let directory):
            if let url = temporaryURLs[variant] { return url }
            let package = directory.appendingPathComponent(variant.rawValue + ".mlpackage")
            guard FileManager.default.fileExists(atPath: package.path) else { throw Failure.modelMissing(variant.rawValue) }
            let lifetime = loadGeneration
            let task = compileTasks[variant] ?? Task { try await MLModel.compileModel(at: package) }
            compileTasks[variant] = task
            defer { if lifetime == loadGeneration { compileTasks[variant] = nil } }
            do {
                let url = try await task.value
                guard lifetime == loadGeneration, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    throw Failure.cancelled
                }
                temporaryURLs[variant] = url
                return url
            } catch let failure as Failure { throw failure }
            catch { throw Failure.modelLoadFailed(error.localizedDescription) }
        }
    }
}

/// Pixel coordinates use a top-left origin. Expansion shifts a crop back into the image
/// rather than shrinking one side, matching the checkpoint's contextual-crop convention.
enum FacePADCrop {
    static func rectangle(imageWidth: Int, imageHeight: Int, faceBounds: CGRect, scale: Double) throws -> CGRect {
        guard imageWidth > 1, imageHeight > 1, scale.isFinite, scale >= 1,
              FaceCaptureFraming.contains(faceBounds) else { throw FacePADModel.Failure.invalidBounds }
        // Ignore sub-pixel floating-point noise at exact pixel boundaries (for example
        // 0.4 + 0.2). Otherwise identical boxes can gain an entire contextual pixel.
        let epsilon = 1e-7
        let x = floor(faceBounds.minX * Double(imageWidth) + epsilon)
        let y = floor(faceBounds.minY * Double(imageHeight) + epsilon)
        let width = ceil(faceBounds.maxX * Double(imageWidth) - epsilon) - x
        let height = ceil(faceBounds.maxY * Double(imageHeight) - epsilon) - y
        guard width >= 2, height >= 2 else { throw FacePADModel.Failure.invalidBounds }
        let clippedScale = min(scale, Double(imageWidth - 1) / width, Double(imageHeight - 1) / height)
        let expandedWidth = width * clippedScale, expandedHeight = height * clippedScale
        let centerX = x + width / 2, centerY = y + height / 2
        var left = centerX - expandedWidth / 2, right = centerX + expandedWidth / 2
        var top = centerY - expandedHeight / 2, bottom = centerY + expandedHeight / 2
        if left < 0 { right -= left; left = 0 }
        if top < 0 { bottom -= top; top = 0 }
        if right > Double(imageWidth - 1) { left -= right - Double(imageWidth - 1); right = Double(imageWidth - 1) }
        if bottom > Double(imageHeight - 1) { top -= bottom - Double(imageHeight - 1); bottom = Double(imageHeight - 1) }
        // The reference crop includes both integer endpoints.
        return CGRect(x: Int(left), y: Int(top), width: Int(right) - Int(left) + 1, height: Int(bottom) - Int(top) + 1)
    }
}

/// Rasterization keeps original RGB values. Only the contextual crop is resized, using
/// half-pixel bilinear sampling and 11-bit coefficients; no recognition alignment or mirroring.
struct FacePADImage {
    let width: Int
    let height: Int
    private let bgra: [UInt8]

    init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1, width <= 16_384, height <= 16_384,
              width * height <= 33_554_432 else { throw FacePADModel.Failure.invalidFrame }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ownSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        let space = ownSpace ?? CGColorSpaceCreateDeviceRGB()
        let format = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: format) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw FacePADModel.Failure.invalidFrame }
        self.width = width
        self.height = height
        bgra = bytes
    }

    func bgrTensor(faceBounds: CGRect, scale: Double) throws -> [Float] {
        let crop = try FacePADCrop.rectangle(imageWidth: width, imageHeight: height, faceBounds: faceBounds, scale: scale)
        let side = FacePADModel.inputSize
        let cropX = Int(crop.minX), cropY = Int(crop.minY), cropWidth = Int(crop.width), cropHeight = Int(crop.height)
        func samples(_ count: Int) -> [(Int, Int, Int, Int)] {
            (0..<side).map { output in
                let position = (Double(output) + 0.5) * Double(count) / Double(side) - 0.5
                let lower = Int(floor(position))
                let fraction = lower < 0 || lower >= count - 1 ? 0 : position - Double(lower)
                let first = max(0, min(count - 1, lower)), second = min(count - 1, first + 1)
                return (first, second, Int(((1 - fraction) * 2048).rounded()), Int((fraction * 2048).rounded()))
            }
        }
        let columns = samples(cropWidth), rows = samples(cropHeight)
        var tensor = [Float](repeating: 0, count: 3 * side * side)
        for row in 0..<side {
            let (y0, y1, by0, by1) = rows[row]
            for column in 0..<side {
                let (x0, x1, ax0, ax1) = columns[column]
                let a = ((cropY + y0) * width + cropX + x0) * 4
                let b = ((cropY + y0) * width + cropX + x1) * 4
                let c = ((cropY + y1) * width + cropX + x0) * 4
                let d = ((cropY + y1) * width + cropX + x1) * 4
                for channel in 0..<3 {
                    let top = Int(bgra[a + channel]) * ax0 + Int(bgra[b + channel]) * ax1
                    let bottom = Int(bgra[c + channel]) * ax0 + Int(bgra[d + channel]) * ax1
                    let value = (top * by0 + bottom * by1 + (1 << 21)) >> 22
                    tensor[channel * side * side + row * side + column] = Float(value)
                }
            }
        }
        return tensor
    }
}
