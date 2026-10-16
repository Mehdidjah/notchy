@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import os
import SwiftUI
import Testing
@testable import Notchy

private func flowIdentity(_ value: Float = 0, model: String = FaceEmbedder.modelIdentifier) -> FaceIdentity {
    FaceIdentity(name: "Test face", samples: [FaceSample(
        descriptor: Array(repeating: value, count: 128), modelIdentifier: model,
        yaw: 0, pitch: 0, quality: 0.8, date: Date()
    )])
}

private func flowAnalysis(index: Int, descriptor: Float = 0) -> FaceFrameAnalysis {
    let turned = (5...7).contains(index)
    let openness = index == 3 ? 0.1 : 0.33
    let geometry = FaceLivenessGeometry(
        leftEyeOpenness: openness, rightEyeOpenness: openness, interocularPixels: 80,
        planePoints: [CGPoint(x: -0.68, y: 0), CGPoint(x: -0.32, y: 0), CGPoint(x: 0.32, y: 0), CGPoint(x: 0.68, y: 0),
                      CGPoint(x: -0.31, y: 1.125), CGPoint(x: 0.31, y: 1.125), CGPoint(x: -0.125, y: 1.025), CGPoint(x: 0.125, y: 1.225)],
        nosePoints: [CGPoint(x: turned ? 0.1 : 0, y: 0.65), CGPoint(x: turned ? 0.1 : 0, y: 0.6)]
    )
    let observation = FaceLivenessObservation(geometry: geometry, yaw: turned ? 22 : 0, pitch: 0, quality: 0.8,
        glare: FaceGlareMeasurement(brightFraction: 0, largestBrightRegionFraction: 0, nativeCropWidth: 180), enclosingDevice: false)
    return FaceFrameAnalysis(face: FaceFrameObservation(bounds: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
        landmarks: FaceLandmarkPoints(), yaw: observation.yaw, pitch: 0, quality: 0.8),
        descriptor: Array(repeating: descriptor, count: 128), faceCount: 1, liveness: observation)
}

private let flowTimes = [0.0, 0.12, 0.24, 0.4, 0.56, 0.7, 0.85, 1.0, 1.2, 1.35]

struct FaceCheckVerificationTests {
    @Test func matchingAStaticPictureNeverAuthorizes() {
        var session = FaceVerificationSession(matcher: FaceMatcher(identities: [flowIdentity()], modelIdentifier: FaceEmbedder.modelIdentifier), direction: .left)
        for index in 0..<100 {
            if case .recognized = session.consume(flowAnalysis(index: 0), timestamp: Double(index) * 0.1) {
                Issue.record("A static face released authorization")
            }
        }
    }

    @Test func sameIdentityMustCompleteTheEntireLiveSequence() {
        var session = FaceVerificationSession(matcher: FaceMatcher(identities: [flowIdentity()], modelIdentifier: FaceEmbedder.modelIdentifier), direction: .left)
        var result: FaceVerificationSession.Result = .waiting("")
        for index in flowTimes.indices { result = session.consume(flowAnalysis(index: index), timestamp: flowTimes[index]) }
        guard case .recognized = result else { Issue.record("The live matching face did not pass: \(result)"); return }
    }

    @Test func twoEnrolledPeopleCannotShareOneChallenge() {
        var session = FaceVerificationSession(matcher: FaceMatcher(identities: [flowIdentity(), flowIdentity(0.2)], modelIdentifier: FaceEmbedder.modelIdentifier), direction: .left)
        for index in flowTimes.indices {
            let frame = flowAnalysis(index: index, descriptor: index < 4 ? 0 : 0.2)
            if case .recognized = session.consume(frame, timestamp: flowTimes[index]) { Issue.record("Mixed identities passed") }
        }
    }

    @Test func denialAndModelFailureRejectEvenWithoutAnEmbedding() {
        for hasDevice in [true, false] {
            var session = FaceVerificationSession(matcher: FaceMatcher(identities: [flowIdentity()], modelIdentifier: FaceEmbedder.modelIdentifier), direction: .left)
            var frame = flowAnalysis(index: 0)
            frame.descriptor = nil
            frame.liveness?.enclosingDevice = hasDevice
            frame.problem = hasDevice ? nil : "Model unavailable"
            guard case .rejected = session.consume(frame, timestamp: 0) else { Issue.record("Missing evidence did not reject"); continue }
        }
    }

    @Test func missedFramesDiscardPreviouslyCompletedBlink() {
        var session = FaceVerificationSession(matcher: FaceMatcher(identities: [flowIdentity()], modelIdentifier: FaceEmbedder.modelIdentifier), direction: .left)
        for index in 0...4 { _ = session.consume(flowAnalysis(index: index), timestamp: flowTimes[index]) }
        _ = session.consume(FaceFrameAnalysis(), timestamp: 0.6)
        for index in 5..<flowTimes.count {
            if case .recognized = session.consume(flowAnalysis(index: index), timestamp: flowTimes[index]) { Issue.record("Interrupted challenge passed") }
        }
    }
}

private struct FlowKey: FaceCheckKeyProvider {
    let key = SymmetricKey(size: .bits256)
    func existingKey() throws -> SymmetricKey? { key }
    func createKey() throws -> SymmetricKey { key }
    func deleteKey() throws {}
}

private final class FlowCamera: FaceCheckCameraCapturing, @unchecked Sendable {
    let session = AVCaptureSession()
    var authorizationStatus: AVAuthorizationStatus = .authorized
    var accessDelay: Duration = .zero
    var startsSuccessfully = true
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var starts: Int { count.withLock { $0 } }
    func requestAuthorization() async -> Bool { try? await Task.sleep(for: accessDelay); return true }
    func start(onFrame: @escaping FaceCheckCamera.FrameHandler, completion: @escaping @Sendable (Bool) -> Void) {
        count.withLock { $0 += 1 }
        completion(startsSuccessfully)
    }
    func stop(completion: (@Sendable () -> Void)?) { completion?() }
}

@MainActor
private func waitForFlow(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
struct FaceCheckControllerFlowTests {
    private func makeStore(_ identity: FaceIdentity? = nil) async throws -> (FaceEnrollmentStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchy-flow-\(UUID())")
        let store = FaceEnrollmentStore(fileURL: directory.appendingPathComponent("identities.sealed"), keyProvider: FlowKey())
        if let identity { try await store.upsert(identity) }
        return (store, directory)
    }

    @Test func emptyStoreRequiresEnrollmentForRevealButAllowsAnOrdinaryAction() async throws {
        let (store, directory) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let camera = FlowCamera(), controller = FaceCheckController(store: store, camera: camera)
        var result: Bool?, needsEnrollment = false
        controller.onNeedsEnrollment = { needsEnrollment = true }
        controller.authorize(reason: "Reveal", requiresEnrollment: true) { result = $0 }
        #expect(await waitForFlow { result != nil })
        #expect(result == false && needsEnrollment)
        result = nil
        controller.authorize(reason: "Clear", requiresEnrollment: false) { result = $0 }
        #expect(await waitForFlow { result != nil })
        #expect(result == true && camera.starts == 0)
        controller.stopCamera()
    }

    @Test func incompatibleEnrollmentNeverBehavesLikeAnEmptyStore() async throws {
        let (store, directory) = try await makeStore(flowIdentity(model: "old-model"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let camera = FlowCamera(), controller = FaceCheckController(store: store, camera: camera)
        var result: Bool?
        controller.authorize(reason: "Clear", requiresEnrollment: false) { result = $0 }
        #expect(await waitForFlow { result != nil })
        #expect(result == false && camera.starts == 0)
        controller.stopCamera()
    }

    @Test func noCameraFramesStillTimeOutAndCancelCompletesOnlyOnce() async throws {
        let (store, directory) = try await makeStore(flowIdentity())
        defer { try? FileManager.default.removeItem(at: directory) }
        let camera = FlowCamera(), controller = FaceCheckController(store: store, camera: camera, checkTimeout: .milliseconds(30))
        var results: [Bool] = []
        controller.authorize(reason: "Clear", requiresEnrollment: false) { results.append($0) }
        #expect(await waitForFlow { controller.liveActivity.phase == .failed })
        #expect(camera.starts == 1 && results.isEmpty)
        controller.cancelVerification()
        controller.cancelVerification()
        #expect(results == [false])
        #expect(controller.cameraState == .off)
    }

    @Test func cancellationDuringPresentationDoesNotStartTheCamera() async throws {
        let (store, directory) = try await makeStore(flowIdentity())
        defer { try? FileManager.default.removeItem(at: directory) }
        let camera = FlowCamera(), controller = FaceCheckController(store: store, camera: camera)
        controller.onBeginCheck = { [weak controller] in controller?.cancelVerification() }
        var result: Bool?
        controller.authorize(reason: "Reveal", requiresEnrollment: true) { result = $0 }
        #expect(await waitForFlow { result != nil })
        #expect(result == false && camera.starts == 0 && controller.cameraState == .off)
    }

    @Test func reentrantReplacementResolvesEveryDisplacedRequest() async throws {
        let (store, directory) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = FaceCheckController(store: store, camera: FlowCamera())
        var results: [String: Bool] = [:]
        controller.authorize(reason: "First", requiresEnrollment: false) { allowed in
            results["first"] = allowed
            if !allowed {
                controller.authorize(reason: "Newest", requiresEnrollment: false) { results["newest"] = $0 }
            }
        }
        controller.authorize(reason: "Displaced", requiresEnrollment: false) { results["displaced"] = $0 }
        #expect(await waitForFlow { results.count == 3 })
        #expect(results == ["first": false, "newest": true, "displaced": false])
        controller.stopCamera()
    }

    @Test func latePermissionGrantDoesNotRestartStoppedCapture() async {
        let camera = FlowCamera()
        camera.authorizationStatus = .notDetermined
        camera.accessDelay = .milliseconds(30)
        let controller = FaceCheckController(camera: camera)
        controller.startCamera()
        await Task.yield()
        controller.stopCamera()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(camera.starts == 0 && controller.cameraState == .off)
    }

    @Test func staleHoverDoesNotSuppressTheNextRetryAndTapDoesNotStealCancel() {
        let activity = FaceCheckLiveActivity()
        var retries = 0
        activity.onRetry = { retries += 1 }
        activity.finish(recognized: false, message: "Retry")
        _ = activity.handleHover(true)
        activity.dismiss()
        activity.begin(reason: "Check")
        activity.finish(recognized: false, message: "Retry")
        _ = activity.handleTap()
        #expect(retries == 1)
        _ = activity.handleHover(true)
        #expect(retries == 2)
        activity.dismiss()
    }

    @Test func aCompletionCanNeverReleaseTwoActions() {
        var results: [Bool] = []
        let request = FaceAuthorizationRequest { results.append($0) }
        request.resolve(true)
        request.resolve(true)
        request.resolve(false)
        #expect(results == [true])
    }
}
