import AppKit
import Combine
import SwiftUI

/// Atoll's floating media controls ("Show floating media controls", off by default): a small
/// black bar with previous, play/pause and next that sits beside the closed notch while music
/// plays, and for 5 s after a pause. Atoll floats it with the private SkyLight window API;
/// this is a plain borderless, non-activating panel at the island's own window level, so it
/// does not show above the lock screen.
@MainActor
final class MediaControlWindowController {
    static let shared = MediaControlWindowController()

    /// Kept on screen this long after playback pauses.
    static let pauseGrace: Duration = .seconds(5)
    /// Waits this long before reappearing, so open/close transitions never flash it.
    static let resumeDelay: Duration = .milliseconds(240)
    /// Gap between the right wing and the bar.
    static let spacing: CGFloat = 36
    /// Closed notch bottom radius the bar's corners are derived from.
    static let notchCornerRadius: CGFloat = 14
    private static let screenInset: CGFloat = 8

    private let manager: MusicManager
    private let settings: MediaSettings
    private let interaction: MediaInteractionState
    private var panel: NSPanel?
    private var hostingView: MediaFirstMouseHostingView<MediaControlOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var graceTask: Task<Void, Never>?
    private var presentTask: Task<Void, Never>?
    private var isShown = false
    private var currentHeight: CGFloat = 0

    init(manager: MusicManager = .shared, settings: MediaSettings = .shared, interaction: MediaInteractionState = .shared) {
        self.manager = manager
        self.settings = settings
        self.interaction = interaction
    }

    func start() {
        guard cancellables.isEmpty else { return }
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$controlWindowEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$liveActivityEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$showStandardMediaControls.map { _ in () }.eraseToAnyPublisher(),
            manager.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            interaction.$closedWings.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(triggers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &cancellables)
        sync()
    }

    func stop() {
        cancellables.removeAll()
        graceTask?.cancel()
        presentTask?.cancel()
        hide(animated: false)
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Whether the bar may show at all: the setting, the music live activity and the
    /// standard controls are on (Atoll's `shouldShowMusicControlWindow`).
    var isAllowed: Bool {
        settings.controlWindowEnabled && settings.liveActivityEnabled && settings.showStandardMediaControls
    }

    private func sync() {
        guard isAllowed, let wings = interaction.closedWings else {
            graceTask?.cancel()
            graceTask = nil
            presentTask?.cancel()
            presentTask = nil
            hide(animated: true)
            return
        }
        if manager.isPlaying {
            graceTask?.cancel()
            graceTask = nil
            if isShown {
                place(wings, animated: true)
            } else {
                schedulePresent()
            }
        } else if isShown {
            place(wings, animated: true)
            guard graceTask == nil else { return }
            graceTask = Task { [weak self] in
                try? await Task.sleep(for: Self.pauseGrace)
                guard !Task.isCancelled, let self else { return }
                self.graceTask = nil
                if !self.manager.isPlaying { self.hide(animated: true) }
            }
        } else {
            presentTask?.cancel()
            presentTask = nil
        }
    }

    private func schedulePresent() {
        guard presentTask == nil else { return }
        presentTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeDelay)
            guard !Task.isCancelled, let self else { return }
            self.presentTask = nil
            guard self.isAllowed, self.manager.isPlaying, let wings = self.interaction.closedWings else { return }
            self.present(wings)
        }
    }

    private func present(_ wings: MediaInteractionState.ClosedWings) {
        let panel = makePanelIfNeeded(height: wings.closedHeight)
        place(wings, animated: false)
        guard !isShown else { return }
        isShown = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            panel.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        guard isShown, let panel else { return }
        isShown = false
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, !self.isShown else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func place(_ wings: MediaInteractionState.ClosedWings, animated: Bool) {
        guard let panel, let hostingView else { return }
        if currentHeight != wings.closedHeight {
            currentHeight = wings.closedHeight
            hostingView.rootView = MediaControlOverlayView(notchHeight: wings.closedHeight, cornerRadius: Self.notchCornerRadius)
        }
        let size = hostingView.fittingSize
        let frame = Self.frame(for: size, screenFrame: wings.screenFrame, centerWidth: wings.centerWidth, wingWidth: wings.wingWidth)
        guard panel.frame != frame else { return }
        if animated, isShown {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Atoll's flyout arithmetic: right of the notch's right wing by `spacing`, flush with
    /// the top of the screen, kept 8 pt inside its right edge.
    static func frame(for size: CGSize, screenFrame: NSRect, centerWidth: CGFloat, wingWidth: CGFloat) -> NSRect {
        let rawX = screenFrame.midX + centerWidth * 0.5 + wingWidth + spacing
        let maxX = screenFrame.maxX - size.width - screenInset
        let x = max(screenFrame.minX + screenInset, min(rawX, maxX))
        return NSRect(
            x: x.rounded(),
            y: (screenFrame.maxY - size.height).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    private func makePanelIfNeeded(height: CGFloat) -> NSPanel {
        if let panel { return panel }
        let hosting = MediaFirstMouseHostingView(rootView: MediaControlOverlayView(notchHeight: height, cornerRadius: Self.notchCornerRadius))
        currentHeight = height
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        self.panel = panel
        self.hostingView = hosting
        return panel
    }
}

/// Lets the first click on the bar press a button even while another app is active.
final class MediaFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The bar itself: three rounded-square buttons 18 pt apart on a black rounded rectangle as
/// tall as the notch. Button side is about 0.94 of the notch height; play/pause is up to
/// 8 pt larger. Track buttons nudge 8 pt when pressed, ±10 s buttons wiggle 11°.
struct MediaControlOverlayView: View {
    let notchHeight: CGFloat
    let cornerRadius: CGFloat

    @ObservedObject private var manager = MusicManager.shared
    @ObservedObject private var settings = MediaSettings.shared

    private static let skipNudge: CGFloat = 8

    private var controlsEnabled: Bool {
        !manager.isPlayerIdle || manager.bundleIdentifier != nil
    }

    var buttonSide: CGFloat { Self.buttonSide(notchHeight: notchHeight) }

    static func buttonSide(notchHeight: CGFloat) -> CGFloat {
        let preferred = notchHeight * 0.94
        let lower = max(30, notchHeight * 0.8)
        let upper = max(notchHeight + 2, 32)
        return min(max(preferred, lower), upper)
    }

    private var playPauseSide: CGFloat { min(buttonSide + 8, notchHeight + 4) }
    private var buttonCornerRadius: CGFloat { max(cornerRadius - 8, buttonSide * 0.28) }
    private var windowCornerRadius: CGFloat { max(cornerRadius - 6, 12) }

    var body: some View {
        let tenSeconds = settings.skipBehavior == .tenSecond
        HStack(spacing: 18) {
            MediaFloatingButton(
                icon: tenSeconds ? "gobackward.10" : "backward.fill",
                side: buttonSide,
                cornerRadius: buttonCornerRadius,
                foreground: .white.opacity(controlsEnabled ? 0.9 : 0.35),
                pressEffect: tenSeconds ? .wiggle(clockwise: false) : .nudge(-Self.skipNudge),
                wiggles: tenSeconds,
                externalTrigger: pulseToken(.backward),
                isEnabled: controlsEnabled
            ) {
                tenSeconds ? manager.seek(by: -MusicManager.seekInterval) : manager.previousTrack()
            }
            MediaFloatingButton(
                icon: manager.isPlaying ? "pause.fill" : "play.fill",
                side: playPauseSide,
                cornerRadius: max(buttonCornerRadius + 2, playPauseSide * 0.32),
                foreground: .white,
                pressEffect: nil,
                wiggles: false,
                externalTrigger: nil,
                isEnabled: controlsEnabled
            ) {
                manager.togglePlay()
            }
            MediaFloatingButton(
                icon: tenSeconds ? "goforward.10" : "forward.fill",
                side: buttonSide,
                cornerRadius: buttonCornerRadius,
                foreground: .white.opacity(controlsEnabled ? 0.9 : 0.35),
                pressEffect: tenSeconds ? .wiggle(clockwise: true) : .nudge(Self.skipNudge),
                wiggles: tenSeconds,
                externalTrigger: pulseToken(.forward),
                isEnabled: controlsEnabled
            ) {
                tenSeconds ? manager.seek(by: MusicManager.seekInterval) : manager.nextTrack()
            }
        }
        .padding(.vertical, max(8, notchHeight * 0.12))
        .padding(.horizontal, 18)
        .frame(height: notchHeight)
        .frame(minWidth: buttonSide * 3.2)
        .background {
            RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous)
                .fill(Color.black)
        }
        .compositingGroup()
        .animation(.smooth(duration: 0.2), value: manager.isPlaying)
        .animation(.smooth(duration: 0.2), value: settings.skipBehavior)
        .animation(.smooth(duration: 0.2), value: controlsEnabled)
    }

    private func pulseToken(_ direction: MusicManager.SkipDirection) -> Int? {
        guard let pulse = manager.skipPulse, pulse.direction == direction else { return nil }
        return pulse.token
    }
}

/// A rounded-square transport button with a white 18 % hover fill and Atoll's press springs.
private struct MediaFloatingButton: View {
    let icon: String
    let side: CGFloat
    let cornerRadius: CGFloat
    let foreground: Color
    let pressEffect: MediaHoverButton.PressEffect?
    let wiggles: Bool
    let externalTrigger: Int?
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var wiggleToken = 0
    @State private var lastExternalTrigger: Int?

    var body: some View {
        Button {
            guard isEnabled else { return }
            playPressEffect()
            action()
        } label: {
            glyph
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering && isEnabled ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotation))
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .onChange(of: externalTrigger) { _, token in
            guard isEnabled, let token, token != lastExternalTrigger else { return }
            lastExternalTrigger = token
            playPressEffect()
        }
    }

    @ViewBuilder
    private var glyph: some View {
        let image = Image(systemName: icon)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(foreground)
        if wiggles, #available(macOS 15.0, *) {
            image.symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
        } else {
            image.contentTransition(.symbolEffect(.replace))
        }
    }

    private func playPressEffect() {
        switch pressEffect {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) { pressOffset = amount }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) { pressOffset = 0 }
            }
        case .wiggle(let clockwise):
            wiggleToken += 1
            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) { rotation = clockwise ? 11 : -11 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { rotation = 0 }
            }
        }
    }
}
