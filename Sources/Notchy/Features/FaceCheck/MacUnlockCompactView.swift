import SwiftUI

/// The hardware cutout stays empty. Only the two flanks carry scan content.
struct MacUnlockGeometry: Equatable {
    var hardwareNotch: Bool
    var closedSize: CGSize

    var expandedBodySize: CGSize {
        hardwareNotch ? CGSize(width: closedSize.width + 84, height: closedSize.height + 12)
                      : CGSize(width: 150, height: 40)
    }
    var expandedSize: CGSize {
        CGSize(width: expandedBodySize.width + (hardwareNotch ? 24 : 0), height: expandedBodySize.height)
    }
    var windowSize: CGSize { CGSize(width: max(320, expandedSize.width + 32), height: expandedSize.height + 100) }
    var topGap: CGFloat { hardwareNotch ? 0 : 3 }
    var lockSize: CGFloat { hardwareNotch ? 16 : 14 }
    var symbolColumnWidth: CGFloat { hardwareNotch ? 40 : 34 }
    var symbolVerticalInset: CGFloat { hardwareNotch ? 11 : 8 }

    func size(expanded: Bool, hovering: Bool = false) -> CGSize {
        let body = expanded ? expandedBodySize : closedSize
        let flare: CGFloat = hardwareNotch ? (expanded ? 12 : 8) : 0
        let bump: CGFloat = expanded && hovering ? 6 : 0
        return CGSize(width: body.width + flare * 2 + bump, height: body.height + bump)
    }

    @MainActor static func resolve(_ screen: NSScreen) -> Self {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return Self(hardwareNotch: false, closedSize: CGSize(width: 80, height: 24))
        }
        return Self(hardwareNotch: true, closedSize: CGSize(width: max(80, right.minX - left.maxX),
                                                           height: screen.safeAreaInsets.top))
    }
}

/// Pure presentation, also used by camera-free previews. A recognized phase is supplied
/// only after the controller observes the matching macOS session unlock.
struct MacUnlockCompactView: View {
    let phase: FaceCheckLiveActivity.Phase
    let geometry: MacUnlockGeometry
    var isExpanded = true
    var isHovering = false
    var animates = true
    var emblemProgress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize { geometry.size(expanded: isExpanded, hovering: isHovering) }
    private var flare: CGFloat { geometry.hardwareNotch ? (isExpanded ? 12 : 8) : 0 }
    private var motion: Bool { animates && !reduceMotion }
    private var unlocked: Bool { phase == .recognized }

    var body: some View {
        let edge = min(geometry.symbolColumnWidth, max(0, size.height - geometry.symbolVerticalInset * 2))
        HStack(spacing: 0) {
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: geometry.lockSize, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(motion ? .smooth(duration: 0.4) : nil, value: unlocked)
                .frame(width: geometry.symbolColumnWidth)
            Spacer(minLength: 0)
            FaceCheckEmblem(phase: phase, animates: animates, progress: emblemProgress,
                            scanStartDelay: geometry.hardwareNotch ? 0.6 : 0.76)
                .frame(width: edge, height: edge)
                .frame(width: geometry.symbolColumnWidth)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, flare + 4)
        .frame(width: size.width, height: size.height)
        .blur(radius: isExpanded || !motion ? 0 : 40)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded || !motion ? 1 : 0.3)
        // The symbols sit inside the body. A rectangular clip avoids re-masking their
        // blurred layer with an animated curve on every opening and closing frame.
        .clipped()
        .background(silhouette.fill(.black))
        .contentShape(silhouette)
        .animation(motion ? .spring(response: 0.45, dampingFraction: isExpanded ? 0.7 : 1) : nil, value: isExpanded)
        .animation(motion ? .easeOut(duration: 0.18) : nil, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked ? "Mac unlocked" : "Mac locked")
    }

    private var silhouette: AnyShape {
        if geometry.hardwareNotch {
            AnyShape(MacUnlockSilhouette(flare: flare, radius: isExpanded ? 22 : 12))
        } else {
            AnyShape(Capsule())
        }
    }
}

struct MacUnlockOverlayView: View {
    @ObservedObject var activity: FaceCheckLiveActivity
    let geometry: MacUnlockGeometry
    var animates = true
    var onHintVisibilityChange: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var hintReady = false
    @State private var lastVisiblePhase: FaceCheckLiveActivity.Phase = .preparing

    private var expanded: Bool { activity.phase != .hidden && activity.phase != .preparing }
    // Preserve the open lock and the result clock through the closing animation.
    private var displayPhase: FaceCheckLiveActivity.Phase { activity.phase == .hidden ? lastVisiblePhase : activity.phase }
    private var canCancel: Bool { activity.phase == .scanning || activity.phase == .failed }
    private var showsHint: Bool { expanded && canCancel && (hovering || hintReady || activity.phase == .failed) }
    private var hintRequest: HintRequest { HintRequest(phase: activity.phase, prompt: activity.prompt) }

    var body: some View {
        VStack(spacing: 6) {
            MacUnlockCompactView(phase: displayPhase, geometry: geometry, isExpanded: expanded,
                                 isHovering: hovering, animates: animates)
                .onTapGesture { activity.retry() }
                .help(activity.phase == .failed && activity.retryAvailable ? "Hover to retry" : activity.prompt)
            if showsHint {
                HStack(spacing: 8) {
                    Text(activity.prompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                    if hovering {
                        Button { activity.cancel() } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7)).frame(width: 22, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel Mac unlock")
                        .help("Cancel Mac unlock")
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 280, height: 40)
                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .help(activity.prompt)
                .transition(.opacity)
            }
        }
        .padding(.top, geometry.topGap)
        .onHover { hovering = $0; activity.handleHover($0) }
        .animation(animates && !reduceMotion ? .easeOut(duration: 0.18) : nil, value: showsHint)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: activity.phase, initial: true) { _, next in
            if next != .hidden { lastVisiblePhase = next }
        }
        .onChange(of: showsHint, initial: true) { _, value in onHintVisibilityChange(value) }
        .task(id: hintRequest) {
            hintReady = false
            guard activity.phase == .scanning, activity.prompt != "Unlocking…" else { return }
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            hintReady = true
        }
        .onExitCommand { activity.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mac unlock. \(activity.prompt)")
    }

    private struct HintRequest: Equatable {
        let phase: FaceCheckLiveActivity.Phase
        let prompt: String
    }
}

private struct MacUnlockSilhouette: Shape {
    var flare: CGFloat
    var radius: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let inset = min(flare, rect.width / 2, rect.height / 2)
        let body = rect.insetBy(dx: inset, dy: 0)
        var path = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: 0,
                                           style: .continuous).path(in: body)
        for side in [-1.0, 1.0] {
            let edge = side < 0 ? body.minX : body.maxX
            path.move(to: CGPoint(x: edge + side * inset, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: edge, y: rect.minY + inset), control: CGPoint(x: edge, y: rect.minY))
            path.addLine(to: CGPoint(x: edge, y: rect.minY))
            path.closeSubpath()
        }
        return path
    }
}
