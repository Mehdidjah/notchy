import Combine
import SwiftUI

/// The open player's transport row is swapped for a level slider while the volume or
/// brightness HUD is up with the island open (`shouldShowControlHUDRow`). This follows the
/// HUD feature's events, both the standard sneak peek and the inline HUD, and stays up 1.5 s
/// after the last one, or while the slider is held.
@MainActor
final class MediaOpenHUDState: ObservableObject {
    static let shared = MediaOpenHUDState()

    enum Kind: Equatable {
        case volume
        case brightness
    }

    /// Sneak-peek duration for HUD events.
    static let displayDuration: Duration = .milliseconds(1_500)

    @Published private(set) var isActive = false
    @Published private(set) var kind: Kind = .volume
    /// 0...1, zero when muted.
    @Published private(set) var level: Double = 0
    @Published private(set) var isMuted = false

    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var isHeld = false

    init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        IslandActivityCenter.shared.sneakPeekRequests
            .receive(on: RunLoop.main)
            .sink { [weak self] peek in
                switch peek.kind {
                // A muted volume peek carries no level.
                case .volume: self?.show(level: peek.level ?? 0, kind: .volume)
                case .brightness: self?.show(level: peek.level ?? 0, kind: .brightness)
                default: break
                }
            }
            .store(in: &cancellables)

        let presenter = SystemHUDPresenter.shared
        Publishers.CombineLatest3(presenter.$isShowingInlineHUD, presenter.$kind, presenter.$level)
            .receive(on: RunLoop.main)
            .sink { [weak self] showing, kind, level in
                guard showing else { return }
                // `if` rather than `switch`, so new HUD kinds elsewhere never break this.
                if kind == .volume {
                    self?.show(level: Double(level), kind: .volume)
                } else if kind == .brightness {
                    self?.show(level: Double(level), kind: .brightness)
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        hideTask?.cancel()
        hideTask = nil
        isHeld = false
        if isActive { isActive = false }
    }

    func show(level newLevel: Double, kind newKind: Kind = .volume) {
        let clamped = min(max(newLevel, 0), 1)
        if kind != newKind { kind = newKind }
        if level != clamped { level = clamped }
        let muted = newKind == .volume && clamped <= 0.001
        if isMuted != muted { isMuted = muted }
        if !isActive {
            withAnimation(.smooth(duration: 0.3)) { isActive = true }
        }
        scheduleHide()
    }

    /// The slider is being dragged: stay up until it is let go.
    func setHeld(_ held: Bool) {
        isHeld = held
        if held {
            hideTask?.cancel()
            hideTask = nil
        } else if isActive {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !isHeld else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled, let self, !self.isHeld else { return }
            self.hideTask = nil
            withAnimation(.smooth(duration: 0.3)) { self.isActive = false }
        }
    }
}

/// The level row: speaker (or sun) glyphs either side of a thin white slider (4 pt, 7 pt
/// while dragged) in a 22-pt band, 10 pt apart. Dragging sets the output volume; the
/// built-in display's brightness has no public setter, so that slider only follows the keys.
struct MediaControlHUDRow: View {
    @ObservedObject var state: MediaOpenHUDState

    @State private var value: Double = 0
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            glyph(leftGlyph)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                MediaCustomSlider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            value = newValue
                            VolumeController.shared.setVolume(Float(newValue))
                        }
                    ),
                    range: 0 ... 1,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: $lastDragged,
                    onValueChange: { VolumeController.shared.setVolume(Float($0)) },
                    restingTrackHeight: 4,
                    draggingTrackHeight: 7
                )
                .frame(height: 7)
                .allowsHitTesting(state.kind == .volume)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            if let rightGlyph {
                glyph(rightGlyph)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { value = state.level }
        .onChange(of: state.level) { _, level in
            guard !dragging else { return }
            // Keys step the level by 1/16; glide between steps instead of jumping.
            withAnimation(.easeOut(duration: 0.18)) { value = level }
        }
        .onChange(of: dragging) { _, held in state.setHeld(held) }
    }

    private var leftGlyph: String {
        switch state.kind {
        case .volume: state.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness: "sun.min.fill"
        }
    }

    private var rightGlyph: String? {
        switch state.kind {
        case .volume: state.isMuted ? nil : "speaker.wave.3"
        case .brightness: "sun.max.fill"
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 22, height: 22, alignment: .center)
    }
}
