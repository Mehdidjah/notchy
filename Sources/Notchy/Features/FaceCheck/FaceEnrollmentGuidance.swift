import Foundation

/// Keep the requested direction steady through settling and both sample holds.
/// The ring conveys capture progress; recovery messages describe unusable input.
enum FaceEnrollmentGuidance {
    static func instruction(event: FaceEnrollmentEvent, next: FaceEnrollmentPose?) -> String {
        switch event {
        case .noFace:
            return "Bring your face into the circle."
        case .unusableDescriptor:
            return "Keep your whole face visible and hold still."
        case .lowQuality:
            return "Hold still in even light."
        case .differentFace:
            return "That doesn't look like the same face. Look straight at the camera."
        case .complete:
            return "All poses captured."
        case .settling, .holding, .captured, .betweenPoses, .centreFirst,
             .wrongPose, .poseAlreadyCaptured, .waitingForVariation:
            return next.map(FaceEnrollmentPresentation.instruction) ?? "All poses captured."
        }
    }

    /// Explains a failed readiness gate without changing which frames the controller accepts.
    static func captureWait(for analysis: FaceFrameAnalysis, profile: FaceRecognitionProfile)
        -> (reason: String, instruction: String) {
        if analysis.faceCount > 1 { return ("multiple faces", "Only one person should be in view.") }
        guard analysis.faceCount == 1, let face = analysis.face else {
            return ("no face", "Bring your face into the circle.")
        }
        if let guidance = analysis.captureGuidance { return ("framing", guidance) }
        guard FaceCaptureFraming.contains(face.bounds) else {
            return ("framing", FaceCaptureFraming.guidance)
        }
        guard let descriptor = analysis.descriptor, analysis.modelIdentifier == profile.identifier,
              profile.prepared(descriptor) != nil else {
            return ("recognition input", "Keep your whole face visible and hold still.")
        }
        guard face.yaw != nil, face.pitch != nil else {
            return ("pose unavailable", "Look toward the camera so both eyes are visible.")
        }
        guard face.quality.isFinite, (0.3...1).contains(face.quality) else {
            return ("capture quality", "Hold still in even light.")
        }
        guard let cues = analysis.liveness, cues.geometry.isUsable else {
            return ("landmarks", "Keep both eyes and your mouth visible.")
        }
        guard cues.glare.isUsable else {
            return ("lighting measurement", "Keep your face evenly lit and fully visible.")
        }
        return ("capture readiness", "Look toward the camera and hold still.")
    }
}
