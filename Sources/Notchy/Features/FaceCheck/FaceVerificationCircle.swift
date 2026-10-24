import SwiftUI

/// Verification uses the same camera circle and result ring as enrollment, without claiming
/// to capture poses or save a new identity during a protected action.
struct FaceVerificationCircle<Preview: View>: View {
    let phase: FaceCheckLiveActivity.Phase
    var animates = true
    @ViewBuilder var preview: () -> Preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var succeeded: Bool { phase == .saved || phase == .recognized }
    private var motion: Bool { animates && !reduceMotion }

    var body: some View {
        ZStack {
            preview()
                .frame(width: FaceEnrollmentPresentation.cameraDiameter,
                       height: FaceEnrollmentPresentation.cameraDiameter)
                .clipShape(Circle())
                .opacity(succeeded || phase == .failed ? 0 : 1)
            FaceEnrollmentRing(counts: [:], samplesPerPose: 2, heading: .init(),
                               saved: succeeded, animates: motion)
            Circle()
                .stroke(FaceEnrollmentPresentation.accent, lineWidth: 14)
                .frame(width: 210, height: 210)
                .opacity(succeeded ? 1 : 0)
            FaceEnrollmentCheckmark()
                .trim(from: 0, to: succeeded ? 1 : 0)
                .stroke(FaceEnrollmentPresentation.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 70, height: 59)
                .offset(y: 4)
            if phase == .failed {
                Image(systemName: "xmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: FaceEnrollmentPresentation.ringDiameter,
               height: FaceEnrollmentPresentation.ringDiameter)
        .animation(motion ? .easeInOut(duration: 0.35) : nil, value: phase)
    }
}
