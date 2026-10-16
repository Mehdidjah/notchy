import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Testing
@testable import Notchy

/// Checks the shipped face-descriptor model against descriptors computed by dlib itself
/// (Tests/NotchyTests/Fixtures/FaceCheckDescriptors.json, written by
/// script/face-model/parity.py). The chips are synthetic and integer-exact: the fixture
/// stores a generator name and seed, and this file rebuilds the same pixels.
@Suite("Face Check descriptor model")
struct FaceCheckEmbedderTests {
    // MARK: Fixture

    struct Sample: Decodable, Sendable {
        let generator: String
        let seed: UInt32
        let rgbChecksum: UInt32
        let descriptor: [Float]

        var name: String { "\(generator)-\(seed)" }
    }

    private struct Fixture: Decodable {
        let samples: [Sample]
    }

    static func loadSamples() throws -> [Sample] {
        let url = try #require(
            Bundle.module.url(forResource: "FaceCheckDescriptors", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).samples
    }

    static let modelPackageURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/Notchy/Features/FaceCheck/Model/FaceDescriptor.mlpackage")

    // MARK: Tests

    @Test func rebuiltChipsMatchTheFixture() throws {
        let samples = try Self.loadSamples()
        #expect(samples.count == 8)
        for sample in samples {
            let rgb = try #require(SyntheticChip.rgb(generator: sample.generator, seed: sample.seed))
            #expect(rgb.count == 150 * 150 * 3)
            #expect(SyntheticChip.fnv1a(rgb) == sample.rgbChecksum, "chip \(sample.name)")
            #expect(sample.descriptor.count == FaceEmbedder.descriptorLength)
        }
    }

    @Test func pixelBufferKeepsTheChipBytes() throws {
        let rgb = try #require(SyntheticChip.rgb(generator: "cartoonNoisy", seed: 5))
        let buffer = try FaceEmbedder.makePixelBuffer(from: try SyntheticChip.image(rgb))
        #expect(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var mismatches = 0
        for row in 0..<150 {
            for column in 0..<150 {
                let pixel = base + row * rowBytes + column * 4
                let source = (row * 150 + column) * 3
                if pixel[2] != rgb[source] || pixel[1] != rgb[source + 1] || pixel[0] != rgb[source + 2] || pixel[3] != 255 {
                    mismatches += 1
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test(arguments: [MLComputeUnits.cpuOnly, .cpuAndNeuralEngine])
    func descriptorsMatchDlib(computeUnits: MLComputeUnits) async throws {
        let samples = try Self.loadSamples()
        let embedder = FaceEmbedder(location: .modelPackage(Self.modelPackageURL), computeUnits: computeUnits)
        var produced: [[Float]] = []
        for sample in samples {
            let rgb = try #require(SyntheticChip.rgb(generator: sample.generator, seed: sample.seed))
            let descriptor = try await embedder.descriptor(for: try SyntheticChip.image(rgb))
            #expect(descriptor.count == FaceEmbedder.descriptorLength)

            let reference = sample.descriptor
            let cosine = Self.cosine(descriptor, reference)
            let distance = FaceEmbedder.distance(descriptor, reference)
            let normRatio = Self.norm(descriptor) / Self.norm(reference)
            let largestGap = zip(descriptor, reference).map { abs($0 - $1) }.max() ?? 0
            print(String(
                format: "face parity [units %d] %@: cosine %.8f distance %.5f max|diff| %.2e norm ratio %.5f",
                computeUnits.rawValue, sample.name, cosine, distance, largestGap, normRatio
            ))
            #expect(cosine >= 0.999, "\(sample.name) cosine \(cosine)")
            // 0.03 is 5% of the 0.6 same-person radius; the fp16 model measures under 0.009.
            #expect(distance < 0.03, "\(sample.name) distance \(distance)")
            #expect(abs(normRatio - 1) < 0.01, "\(sample.name) norm ratio \(normRatio)")
            produced.append(descriptor)
        }

        // Each output is nearest to its own reference, so the comparison above can't pass by
        // accident (different chips sit 0.16 or more apart).
        for (index, descriptor) in produced.enumerated() {
            let distances = samples.map { FaceEmbedder.distance(descriptor, $0.descriptor) }
            #expect(distances.firstIndex(of: distances.min()!) == index, "\(samples[index].name)")
        }
    }

    @Test func pixelBufferAndImageInputsAgree() async throws {
        let rgb = try #require(SyntheticChip.rgb(generator: "cartoon", seed: 0))
        let image = try SyntheticChip.image(rgb)
        let embedder = FaceEmbedder(location: .modelPackage(Self.modelPackageURL), computeUnits: .cpuOnly)
        let fromImage = try await embedder.descriptor(for: image)
        let fromBuffer = try await embedder.descriptor(for: try FaceEmbedder.makePixelBuffer(from: image))
        #expect(FaceEmbedder.distance(fromImage, fromBuffer) < 1e-5)
        #expect(await embedder.isLoaded)
        await embedder.unload()
        #expect(await !embedder.isLoaded)
    }

    @Test func chipsOfTheWrongSizeAreRejectedBeforeLoading() async throws {
        let embedder = FaceEmbedder(location: .compiledModel(URL(fileURLWithPath: "/nonexistent/Face.mlmodelc")))
        let small = try SyntheticChip.image([UInt8](repeating: 128, count: 120 * 150 * 3), width: 120, height: 150)
        await #expect(throws: FaceEmbedder.Failure.wrongChipSize(width: 120, height: 150)) {
            try await embedder.descriptor(for: small)
        }
        #expect(await !embedder.isLoaded)
    }

    @Test func unsupportedPixelFormatsAreRejected() async throws {
        let format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let embedder = FaceEmbedder(location: .modelPackage(Self.modelPackageURL))
        await #expect(throws: FaceEmbedder.Failure.unsupportedPixelFormat(format)) {
            var created: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 150, 150, format, nil, &created)
            guard let buffer = created else { return }
            try await embedder.descriptor(for: buffer)
        }
        #expect(await !embedder.isLoaded)
    }

    @Test func aMissingModelIsReported() async {
        // The test runner's main bundle has no compiled model, like a build made without Xcode.
        await #expect(throws: FaceEmbedder.Failure.modelMissing) {
            try await FaceEmbedder(location: .appBundle).prepare()
        }
        await #expect(throws: FaceEmbedder.Failure.modelMissing) {
            try await FaceEmbedder(location: .modelPackage(URL(fileURLWithPath: "/nonexistent/Face.mlpackage"))).prepare()
        }
    }

    @Test func distanceIsEuclidean() {
        #expect(FaceEmbedder.distance([0, 0, 0], [3, 4, 0]) == 5)
        #expect(FaceEmbedder.distance([1, 2], [1, 2]) == 0)
    }

    // MARK: Helpers

    static func norm(_ v: [Float]) -> Float { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } / (norm(a) * norm(b))
    }
}

/// The synthetic 150x150 RGB chips of script/face-model/parity.py, rebuilt with the same
/// integer arithmetic.
enum SyntheticChip {
    static let side = 150

    static func rgb(generator: String, seed: UInt32) -> [UInt8]? {
        switch generator {
        case "noise": return noise(seed: seed)
        case "gradient": return planes { r, c in [r * 255 / 149, c * 255 / 149, (r + c) * 255 / 298] }
        case "rings": return rings()
        case "blocks": return blocks(seed: seed)
        case "cartoon": return cartoon().map(UInt8.init)
        case "cartoonNoisy": return cartoonNoisy(seed: seed)
        default: return nil
        }
    }

    static func xorshift(_ state: inout UInt32) -> UInt8 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return UInt8(state >> 24)
    }

    static func fnv1a(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(UInt32(0x811C_9DC5)) { ($0 ^ UInt32($1)) &* 0x0100_0193 }
    }

    static func image(_ rgb: [UInt8], width: Int = side, height: Int = side) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(rgb) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private static func planes(_ pixel: (Int, Int) -> [Int]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(side * side * 3)
        for r in 0..<side {
            for c in 0..<side {
                out.append(contentsOf: pixel(r, c).map(UInt8.init))
            }
        }
        return out
    }

    private static func noise(seed: UInt32) -> [UInt8] {
        var state = seed
        return (0..<(side * side * 3)).map { _ in xorshift(&state) }
    }

    private static func rings() -> [UInt8] {
        planes { r, c in
            let d2 = (r - 75) * (r - 75) + (c - 75) * (c - 75)
            return [255 - min(255, d2 * 255 / 11250), (d2 / 23) % 256, (r * c / 89) % 256]
        }
    }

    private static func blocks(seed: UInt32) -> [UInt8] {
        var state = seed
        var colours: [[UInt8]] = []
        for _ in 0..<(15 * 15) {
            colours.append([xorshift(&state), xorshift(&state), xorshift(&state)])
        }
        var out: [UInt8] = []
        for r in 0..<side {
            for c in 0..<side {
                out.append(contentsOf: colours[(r / 10) * 15 + c / 10])
            }
        }
        return out
    }

    private static func cartoon() -> [Int] {
        // centre row, centre column, radius rows, radius columns, colour; later ones on top
        let shapes: [(Int, Int, Int, Int, [Int])] = [
            (62, 75, 52, 50, [58, 40, 30]),
            (82, 75, 58, 46, [226, 178, 146]),
            (64, 56, 5, 10, [245, 245, 240]),
            (64, 94, 5, 10, [245, 245, 240]),
            (64, 56, 4, 4, [52, 38, 32]),
            (64, 94, 4, 4, [52, 38, 32]),
            (54, 56, 2, 11, [70, 50, 38]),
            (54, 94, 2, 11, [70, 50, 38]),
            (88, 75, 11, 5, [206, 152, 122]),
            (110, 75, 5, 17, [164, 72, 70]),
        ]
        var out: [Int] = []
        out.reserveCapacity(side * side * 3)
        for r in 0..<side {
            for c in 0..<side {
                var colour = [92, 96, 108]
                for (cy, cx, ry, rx, fill) in shapes
                where (c - cx) * (c - cx) * ry * ry + (r - cy) * (r - cy) * rx * rx <= rx * rx * ry * ry {
                    colour = fill
                }
                out.append(contentsOf: colour)
            }
        }
        return out
    }

    private static func cartoonNoisy(seed: UInt32) -> [UInt8] {
        var state = seed
        return cartoon().map { value in
            let jitter = Int(xorshift(&state)) % 25 - 12
            return UInt8(min(255, max(0, value + jitter)))
        }
    }
}
