import SwiftUI

/// One enrollment composition shared by the live camera and offline presentation checks.
struct FaceEnrollmentScanView<Preview: View>: View {
    var counts: [FaceEnrollmentPose: Int]
    var samplesPerPose: Int = FaceEnrollmentRules.standard.samplesPerPose
    var heading = FaceEnrollmentPresentation.Heading()
    var instruction: String
    var phase: FaceEnrollmentScanPhase = .scanning
    var hasHardwareNotch = true
    var isExpanded = true
    var compactWidth: CGFloat = 190
    var compactHeight: CGFloat = 32
    var animates = true
    var drawsBackground = true
    var cancel: () -> Void
    var retry: () -> Void = {}
    @ViewBuilder var preview: () -> Preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Bool { animates && !reduceMotion }
    private var width: CGFloat { FaceEnrollmentPresentation.bodyWidth + (hasHardwareNotch ? FaceEnrollmentPresentation.flare * 2 : 0) }
    private var height: CGFloat { hasHardwareNotch ? FaceEnrollmentPresentation.height : 350 }

    var body: some View {
        ZStack(alignment: .top) {
            if drawsBackground {
                silhouette.fill(.black)
                    .frame(width: isExpanded ? width : compactWidth,
                           height: isExpanded ? height : compactHeight)
            }
            content
                .opacity(isExpanded ? 1 : 0)
                .animation(motion ? .easeOut(duration: 0.2).delay(isExpanded ? 0.15 : 0) : nil,
                           value: isExpanded)
        }
        .frame(width: width, height: height, alignment: .top)
        .clipShape(silhouette)
        .animation(motion ? .spring(response: 0.45, dampingFraction: isExpanded ? 0.7 : 1) : nil,
                   value: isExpanded)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: cancel)
    }

    private var silhouette: AnyShape {
        if hasHardwareNotch {
            AnyShape(FaceEnrollmentSilhouette())
        } else {
            AnyShape(RoundedRectangle(cornerRadius: FaceEnrollmentPresentation.bottomRadius, style: .continuous))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZStack {
                preview()
                    .frame(width: FaceEnrollmentPresentation.cameraDiameter, height: FaceEnrollmentPresentation.cameraDiameter)
                    .clipShape(Circle())
                    .opacity(phase.isSaved || phase.failure != nil ? 0 : 1)
                    .animation(motion ? .easeInOut(duration: 0.4) : nil, value: phase)
                    .accessibilityLabel("Live mirrored camera preview")
                ring
                Circle()
                    .stroke(FaceEnrollmentPresentation.accent, lineWidth: 14)
                    .frame(width: 210, height: 210)
                    .scaleEffect(phase.isSaved ? 1 : 0.92)
                    .opacity(phase.isSaved ? 1 : 0)
                    .animation(motion ? .easeInOut(duration: 0.45) : nil, value: phase.isSaved)
                FaceEnrollmentCheckmark()
                    .trim(from: 0, to: phase.isSaved ? 1 : 0)
                    .stroke(FaceEnrollmentPresentation.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 70, height: 59)
                    .offset(y: 4)
                    .animation(motion ? .easeOut(duration: 0.28).delay(0.2) : nil, value: phase.isSaved)
                if phase.failure != nil {
                    Image(systemName: "xmark")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: FaceEnrollmentPresentation.ringDiameter, height: FaceEnrollmentPresentation.ringDiameter)
            .padding(.top, hasHardwareNotch ? 40 : 30)
            Spacer(minLength: 8)
            if let failure = phase.failure {
                VStack(spacing: 4) {
                    Text(failure).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Button("Try again", action: retry).buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FaceEnrollmentPresentation.accent)
                }
                .padding(.bottom, 8)
            } else {
                Text(phase.isSaved ? "Face saved" : phase == .saving ? "Saving your face…" : instruction)
                    .lineLimit(2)
                    .padding(.bottom, 30)
                    .contentTransition(.opacity)
                    .animation(motion ? .easeInOut(duration: 0.2) : nil, value: instruction)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .frame(width: FaceEnrollmentPresentation.bodyWidth, height: height)
        .overlay(alignment: .topTrailing) {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel face scan")
            .accessibilityLabel("Cancel face scan")
            .padding(18)
        }
    }

    private var ring: some View {
        FaceEnrollmentRing(counts: counts, samplesPerPose: samplesPerPose, heading: heading,
                           saved: phase.isSaved, animates: motion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Face scan progress")
        .accessibilityValue("\(counts.values.filter { $0 >= samplesPerPose }.count) of 9 positions captured")
    }
}

/// System continuous corners for the body, with two small concave paths joining the top
/// edge to the menu bar. Composing paths avoids approximating the system corner curve.
struct FaceEnrollmentSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(FaceEnrollmentPresentation.flare, rect.width / 2, rect.height / 2)
        let body = rect.insetBy(dx: inset, dy: 0)
        var path = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: FaceEnrollmentPresentation.bottomRadius,
                                           bottomTrailingRadius: FaceEnrollmentPresentation.bottomRadius, topTrailingRadius: 0,
                                           style: .continuous).path(in: body)
        for side in [-1.0, 1.0] {
            let edge = side < 0 ? body.minX : body.maxX
            path.move(to: CGPoint(x: edge + side * inset, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.minY + inset),
                              control: CGPoint(x: edge, y: rect.minY))
            path.addLine(to: CGPoint(x: edge, y: rect.minY))
            path.closeSubpath()
        }
        return path
    }
}

struct FaceEnrollmentCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY - 7))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 5))
        }
    }
}
