import Combine
import SwiftUI

/// Which system event the HUD is showing.
enum SystemHUDKind: String, Sendable, Equatable {
    case volume
    case brightness
    case microphone
}

/// Owns what the system HUD shows and for how long, the sneak-peek
/// coordination that volume and microphone events use.
///
/// Inline style: sets `isShowingInlineHUD`, which `InlineHUDActivity` turns into wings on
/// the closed notch, and hides it 1.5 s after the last event. Standard style: hands the
/// island a level sneak peek instead.
@MainActor
final class SystemHUDPresenter: ObservableObject {
    static let shared = SystemHUDPresenter()

    /// Default sneak-peek duration.
    static let displayDuration: Duration = .milliseconds(1_500)
    /// Every sneak-peek update is written inside this animation.
    static let updateAnimation = Animation.smooth(duration: 0.3)

    @Published private(set) var kind: SystemHUDKind = .volume
    /// 0...1; zero means muted.
    @Published private(set) var level: CGFloat = 0
    /// Output is Bluetooth, so the volume glyph is headphones.
    @Published private(set) var isBluetoothOutput = false
    @Published private(set) var isShowingInlineHUD = false {
        didSet {
            if oldValue != isShowingInlineHUD { inlineVisibilityDidChange.send() }
        }
    }
    /// While locked the island cannot be seen, so the HUD stands down.
    @Published var isScreenLocked = false {
        didSet { if isScreenLocked { hideInlineHUD() } }
    }

    /// Fires when the inline HUD appears or disappears.
    let inlineVisibilityDidChange = PassthroughSubject<Void, Never>()

    let settings: SystemHUDSettings
    private let activityCenter: IslandActivityCenter
    private var hideTask: Task<Void, Never>?
    private var volumeSuppressedUntil: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(settings: SystemHUDSettings = .shared, activityCenter: IslandActivityCenter = .shared) {
        self.settings = settings
        self.activityCenter = activityCenter
    }

    // MARK: Showing

    /// Shows a volume level (zero when muted). Ignored while the HUD is off, the volume HUD
    /// is off, the screen is locked, or another feature asked for silence.
    func presentVolume(level: CGFloat, isBluetooth: Bool) {
        guard settings.enableSystemHUD, settings.enableVolumeHUD, !isScreenLocked else { return }
        guard !isVolumeHUDSuppressed else { return }
        present(kind: .volume, level: level, isBluetooth: isBluetooth)
    }

    /// Shows the built-in display's brightness after the user changed it.
    func presentBrightness(level: CGFloat) {
        guard settings.enableSystemHUD, settings.enableBrightnessHUD, !isScreenLocked else { return }
        present(kind: .brightness, level: level, isBluetooth: isBluetoothOutput)
    }

    /// Shows the microphone's mute state ("Mic muted" / "unmuted").
    func presentMicrophone(isMuted: Bool) {
        guard settings.enableSystemHUD, settings.enableMicrophoneHUD, !isScreenLocked else { return }
        present(kind: .microphone, level: isMuted ? 0 : 1, isBluetooth: isBluetoothOutput)
    }

    private func present(kind: SystemHUDKind, level: CGFloat, isBluetooth: Bool) {
        let clamped = min(max(level, 0), 1)
        if settings.usesInlineStyle {
            withAnimation(Self.updateAnimation) {
                self.kind = kind
                self.level = clamped
                self.isBluetoothOutput = isBluetooth
                self.isShowingInlineHUD = true
            }
            scheduleHide()
        } else {
            hideInlineHUD()
            self.kind = kind
            self.level = clamped
            self.isBluetoothOutput = isBluetooth
            activityCenter.requestSneakPeek(Self.standardSneakPeek(kind: kind, level: clamped, isBluetooth: isBluetooth))
        }
    }

    /// The level bar in the inline HUD was dragged: show the new level at once and keep the
    /// HUD up while the pointer is busy (every value write re-arms the hide). The standard row keeps its own drag state.
    func userDidDrag(to value: CGFloat) {
        guard isShowingInlineHUD, kind == .volume else { return }
        level = min(max(value, 0), 1)
        scheduleHide()
    }

    func hideInlineHUD() {
        hideTask?.cancel()
        hideTask = nil
        guard isShowingInlineHUD else { return }
        withAnimation(Self.updateAnimation) { isShowingInlineHUD = false }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            withAnimation(Self.updateAnimation) { self.isShowingInlineHUD = false }
        }
    }

    // MARK: Suppression

    /// Keeps the volume HUD quiet for a while, for example while another control in the
    /// island moves the volume itself.
    func suppressVolumeHUD(for seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let proposed = clock.now + .milliseconds(Int(seconds * 1_000))
        if let current = volumeSuppressedUntil, current > proposed { return }
        volumeSuppressedUntil = proposed
    }

    var isVolumeHUDSuppressed: Bool {
        guard let until = volumeSuppressedUntil else { return false }
        if clock.now < until { return true }
        volumeSuppressedUntil = nil
        return false
    }

    // MARK: Symbols and text

    /// Speaker glyph: zero is the slashed speaker, then one, two or three waves.
    static func speakerSymbolName(for level: CGFloat) -> String {
        switch level {
        case 0: "speaker.slash.fill"
        case 0...0.3: "speaker.wave.1.fill"
        case 0.3...0.8: "speaker.wave.2.fill"
        case 0.8...1: "speaker.wave.3.fill"
        default: "speaker.wave.2.fill"
        }
    }

    /// Volume glyph: headphones on a Bluetooth route, otherwise the speaker for the level.
    static func volumeSymbolName(for level: CGFloat, isBluetooth: Bool) -> String {
        isBluetooth ? "headphones" : speakerSymbolName(for: level)
    }

    /// Brightness glyph: the small sun up to 60 %, the large one above.
    static func brightnessSymbolName(for level: CGFloat) -> String {
        level > 0.6 ? "sun.max.fill" : "sun.min.fill"
    }

    static func microphoneSymbolName(isMuted: Bool) -> String {
        isMuted ? "mic.slash.fill" : "mic.fill"
    }

    /// Percentage label: the rounded percentage, right-aligned in three columns.
    static func percentageText(for level: CGFloat) -> String {
        let percent = max(0, min(100, Int((level * 100).rounded())))
        return String(format: "%3d", percent)
    }

    /// The standard-style peek: a level row for volume (a "muted" line at zero), a text line
    /// for the microphone. The standard row always draws the speaker for the level, even
    /// on a Bluetooth route (only the inline HUD swaps in headphones).
    static func standardSneakPeek(kind: SystemHUDKind, level: CGFloat, isBluetooth: Bool) -> SneakPeek {
        switch kind {
        case .volume:
            let symbol = speakerSymbolName(for: level)
            if level <= 0 {
                return SneakPeek(kind: .volume, systemImage: symbol, title: "muted", tint: .white,
                                 duration: displayDuration)
            }
            return SneakPeek(kind: .volume, systemImage: symbol, title: "Volume", level: Double(level),
                             tint: .white, duration: displayDuration)
        case .brightness:
            return SneakPeek(kind: .brightness, systemImage: brightnessSymbolName(for: level), title: "Brightness",
                             level: Double(level), tint: .white, duration: displayDuration)
        case .microphone:
            let muted = level <= 0
            return SneakPeek(kind: .generic, systemImage: microphoneSymbolName(isMuted: muted),
                             title: muted ? "Mic muted" : "Mic unmuted", tint: .white,
                             duration: displayDuration)
        }
    }
}
