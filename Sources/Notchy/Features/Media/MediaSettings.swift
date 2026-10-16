import Combine
import Foundation

/// Media preferences, stored under "media." keys with Atoll's defaults.
@MainActor
final class MediaSettings: ObservableObject {
    static let shared = MediaSettings()

    enum Key {
        static let sourcePreference = "media.sourcePreference"
        static let waitInterval = "media.waitInterval"
        static let showStandardMediaControls = "media.showStandardMediaControls"
        static let autoHideInactivePlayer = "media.autoHideInactivePlayer"
        static let customizableControls = "media.customizableControls"
        static let controlSlots = "media.controlSlots"
        static let skipBehavior = "media.skipBehavior"
        static let liveActivityEnabled = "media.liveActivityEnabled"
        static let enableSneakPeek = "media.enableSneakPeek"
        static let sneakPeekOnTrackChange = "media.sneakPeekOnTrackChange"
        static let enableLyrics = "media.enableLyrics"
        static let lyricsPanelWidth = "media.lyricsPanelWidth"
        static let parallaxIntensity = "media.parallaxIntensity"
        static let showSongMetadataInClosedNotch = "media.showSongMetadataInClosedNotch"
        static let useMusicVisualizer = "media.useMusicVisualizer"
        static let visualizerBarCount = "media.visualizerBarCount"
        static let coloredSpectrogram = "media.coloredSpectrogram"
        static let colorExtractionMode = "media.colorExtractionMode"
        static let playerColorTinting = "media.playerColorTinting"
        static let sliderColor = "media.sliderColor"
        static let lightingEffect = "media.lightingEffect"
        static let cornerRadiusScaling = "media.cornerRadiusScaling"
        static let horizontalGestures = "media.horizontalGestures"
        static let gestureBehavior = "media.gestureBehavior"
        static let reverseSwipeGestures = "media.reverseSwipeGestures"
        static let showMediaOutputControl = "media.showMediaOutputControl"
        static let lyricHighlightStyle = "media.lyricHighlightStyle"
        static let lyricsPanelOffset = "media.lyricsPanelOffset"
        static let sneakPeekStyle = "media.sneakPeekStyle"
        static let controlWindowEnabled = "media.controlWindowEnabled"
    }

    enum Default {
        static let sourcePreference = MediaSourcePreference.automatic
        static let waitInterval: Double = 3
        static let lyricsPanelWidth: Double = 280
        static let lyricsPanelOffset: Double = 0
        static let parallaxIntensity: Double = 6
        static let visualizerBarCount = 4
        static let visualizerBarCounts = [4, 5, 6]
    }

    private let defaults: UserDefaults

    /// Which player the notch follows.
    @Published var sourcePreference: MediaSourcePreference {
        didSet { defaults.set(sourcePreference.rawValue, forKey: Key.sourcePreference) }
    }
    /// Seconds after a pause before the player counts as idle ("Media inactivity timeout").
    @Published var waitInterval: Double {
        didSet { defaults.set(waitInterval, forKey: Key.waitInterval) }
    }
    /// "Show media controls in Dynamic Island".
    @Published var showStandardMediaControls: Bool {
        didSet { defaults.set(showStandardMediaControls, forKey: Key.showStandardMediaControls) }
    }
    /// "Auto-hide inactive notch media player".
    @Published var autoHideInactivePlayer: Bool {
        didSet { defaults.set(autoHideInactivePlayer, forKey: Key.autoHideInactivePlayer) }
    }
    /// "Enable customizable controls" (Atoll's showShuffleAndRepeat).
    @Published var customizableControls: Bool {
        didSet { defaults.set(customizableControls, forKey: Key.customizableControls) }
    }
    @Published var controlSlots: [MediaControlSlot] {
        didSet { defaults.set(controlSlots.map(\.rawValue), forKey: Key.controlSlots) }
    }
    /// What the skip buttons do when customizable controls are off.
    @Published var skipBehavior: MediaSkipBehavior {
        didSet { defaults.set(skipBehavior.rawValue, forKey: Key.skipBehavior) }
    }
    /// Artwork and spectrum wings on the closed notch.
    @Published var liveActivityEnabled: Bool {
        didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivityEnabled) }
    }
    @Published var enableSneakPeek: Bool {
        didSet { defaults.set(enableSneakPeek, forKey: Key.enableSneakPeek) }
    }
    /// "Show sneak peek on playback changes".
    @Published var sneakPeekOnTrackChange: Bool {
        didSet { defaults.set(sneakPeekOnTrackChange, forKey: Key.sneakPeekOnTrackChange) }
    }
    @Published var enableLyrics: Bool {
        didSet { defaults.set(enableLyrics, forKey: Key.enableLyrics) }
    }
    /// Width of the side lyrics panel shown when the calendar is off.
    @Published var lyricsPanelWidth: Double {
        didSet { defaults.set(lyricsPanelWidth, forKey: Key.lyricsPanelWidth) }
    }
    /// Degrees of artwork tilt at the edge of a hover; 0 disables the effect.
    @Published var parallaxIntensity: Double {
        didSet { defaults.set(parallaxIntensity, forKey: Key.parallaxIntensity) }
    }
    /// "Show song title and artist on non-notch displays".
    @Published var showSongMetadataInClosedNotch: Bool {
        didSet { defaults.set(showSongMetadataInClosedNotch, forKey: Key.showSongMetadataInClosedNotch) }
    }
    @Published var useMusicVisualizer: Bool {
        didSet { defaults.set(useMusicVisualizer, forKey: Key.useMusicVisualizer) }
    }
    /// "Visualizer candles": 4, 5 or 6.
    @Published var visualizerBarCount: Int {
        didSet { defaults.set(visualizerBarCount, forKey: Key.visualizerBarCount) }
    }
    /// Tint the spectrum and closed text with the artwork colour.
    @Published var coloredSpectrogram: Bool {
        didSet { defaults.set(coloredSpectrogram, forKey: Key.coloredSpectrogram) }
    }
    @Published var colorExtractionMode: MediaColorExtractionMode {
        didSet { defaults.set(colorExtractionMode.rawValue, forKey: Key.colorExtractionMode) }
    }
    /// Tint the artist line and time labels with the artwork colour.
    @Published var playerColorTinting: Bool {
        didSet { defaults.set(playerColorTinting, forKey: Key.playerColorTinting) }
    }
    @Published var sliderColor: MediaSliderColor {
        didSet { defaults.set(sliderColor.rawValue, forKey: Key.sliderColor) }
    }
    /// Blurred artwork glow behind the open player's cover.
    @Published var lightingEffect: Bool {
        didSet { defaults.set(lightingEffect, forKey: Key.lightingEffect) }
    }
    /// 13-pt artwork corners in the open player instead of 4 pt.
    @Published var cornerRadiusScaling: Bool {
        didSet { defaults.set(cornerRadiusScaling, forKey: Key.cornerRadiusScaling) }
    }
    /// Two-finger horizontal swipes skip tracks (when the host forwards them).
    @Published var horizontalGestures: Bool {
        didSet { defaults.set(horizontalGestures, forKey: Key.horizontalGestures) }
    }
    @Published var gestureBehavior: MediaSkipBehavior {
        didSet { defaults.set(gestureBehavior.rawValue, forKey: Key.gestureBehavior) }
    }
    /// "Reverse swipe gestures": a swipe to the right skips forward instead.
    @Published var reverseSwipeGestures: Bool {
        didSet { defaults.set(reverseSwipeGestures, forKey: Key.reverseSwipeGestures) }
    }
    /// "Show \"Change Media Output\" control": offers the output picker in the slots.
    @Published var showMediaOutputControl: Bool {
        didSet { defaults.set(showMediaOutputControl, forKey: Key.showMediaOutputControl) }
    }
    /// "Highlight": how the current lyric line is marked in the side panel.
    @Published var lyricHighlightStyle: MediaLyricHighlightStyle {
        didSet { defaults.set(lyricHighlightStyle.rawValue, forKey: Key.lyricHighlightStyle) }
    }
    /// "Side lyrics horizontal offset", -100...100 pt.
    @Published var lyricsPanelOffset: Double {
        didSet { defaults.set(lyricsPanelOffset, forKey: Key.lyricsPanelOffset) }
    }
    /// "Sneak Peek Style": the grey line under the notch, or the widened inline notch.
    @Published var sneakPeekStyle: MediaSneakPeekStyle {
        didSet { defaults.set(sneakPeekStyle.rawValue, forKey: Key.sneakPeekStyle) }
    }
    /// "Show floating media controls" beside the closed notch.
    @Published var controlWindowEnabled: Bool {
        didSet { defaults.set(controlWindowEnabled, forKey: Key.controlWindowEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sourcePreference = Self.enumValue(defaults, Key.sourcePreference, Default.sourcePreference)
        waitInterval = Self.clamped(defaults.object(forKey: Key.waitInterval) as? Double ?? Default.waitInterval, 0, 10)
        showStandardMediaControls = defaults.object(forKey: Key.showStandardMediaControls) as? Bool ?? true
        autoHideInactivePlayer = defaults.object(forKey: Key.autoHideInactivePlayer) as? Bool ?? true
        customizableControls = defaults.object(forKey: Key.customizableControls) as? Bool ?? true
        if let raw = defaults.stringArray(forKey: Key.controlSlots) {
            let slots = raw.compactMap(MediaControlSlot.init(rawValue:))
            controlSlots = slots.count == MediaControlSlot.slotCount ? slots : MediaControlSlot.defaultLayout
        } else {
            controlSlots = MediaControlSlot.defaultLayout
        }
        skipBehavior = Self.enumValue(defaults, Key.skipBehavior, .track)
        liveActivityEnabled = defaults.object(forKey: Key.liveActivityEnabled) as? Bool ?? true
        enableSneakPeek = defaults.object(forKey: Key.enableSneakPeek) as? Bool ?? false
        sneakPeekOnTrackChange = defaults.object(forKey: Key.sneakPeekOnTrackChange) as? Bool ?? true
        enableLyrics = defaults.object(forKey: Key.enableLyrics) as? Bool ?? false
        lyricsPanelWidth = Self.clamped(
            defaults.object(forKey: Key.lyricsPanelWidth) as? Double ?? Default.lyricsPanelWidth, 180, 420)
        parallaxIntensity = Self.clamped(
            defaults.object(forKey: Key.parallaxIntensity) as? Double ?? Default.parallaxIntensity, 0, 12)
        showSongMetadataInClosedNotch = defaults.object(forKey: Key.showSongMetadataInClosedNotch) as? Bool ?? false
        useMusicVisualizer = defaults.object(forKey: Key.useMusicVisualizer) as? Bool ?? true
        let storedBars = defaults.object(forKey: Key.visualizerBarCount) as? Int ?? Default.visualizerBarCount
        visualizerBarCount = Default.visualizerBarCounts.contains(storedBars) ? storedBars : Default.visualizerBarCount
        coloredSpectrogram = defaults.object(forKey: Key.coloredSpectrogram) as? Bool ?? true
        colorExtractionMode = Self.enumValue(defaults, Key.colorExtractionMode, .vibrant)
        playerColorTinting = defaults.object(forKey: Key.playerColorTinting) as? Bool ?? true
        sliderColor = Self.enumValue(defaults, Key.sliderColor, .white)
        lightingEffect = defaults.object(forKey: Key.lightingEffect) as? Bool ?? true
        cornerRadiusScaling = defaults.object(forKey: Key.cornerRadiusScaling) as? Bool ?? true
        horizontalGestures = defaults.object(forKey: Key.horizontalGestures) as? Bool ?? true
        gestureBehavior = Self.enumValue(defaults, Key.gestureBehavior, .track)
        reverseSwipeGestures = defaults.object(forKey: Key.reverseSwipeGestures) as? Bool ?? false
        showMediaOutputControl = defaults.object(forKey: Key.showMediaOutputControl) as? Bool ?? true
        lyricHighlightStyle = Self.enumValue(defaults, Key.lyricHighlightStyle, .sweep)
        lyricsPanelOffset = Self.clamped(
            defaults.object(forKey: Key.lyricsPanelOffset) as? Double ?? Default.lyricsPanelOffset, -100, 100)
        sneakPeekStyle = Self.enumValue(defaults, Key.sneakPeekStyle, .standard)
        controlWindowEnabled = defaults.object(forKey: Key.controlWindowEnabled) as? Bool ?? false
    }

    /// The slots the open player draws, following Atoll's rules: the configured layout when
    /// customizable controls are on (falling back to the default when every slot is empty),
    /// otherwise the minimal or ±10 s layout.
    func displayedSlots(canFavorite: Bool, isAppleMusicActive: Bool = true) -> [MediaControlSlot] {
        if customizableControls {
            let normalized = controlSlots.normalizedSlots(
                canFavorite: canFavorite,
                allowsMediaOutput: showMediaOutputControl,
                isAppleMusicActive: isAppleMusicActive
            )
            return normalized.contains(where: { $0 != .none }) ? normalized : MediaControlSlot.defaultLayout
        }
        switch skipBehavior {
        case .track: return MediaControlSlot.minimalLayout
        case .tenSecond: return MediaControlSlot.tenSecondLayout
        }
    }

    func setSlot(_ slot: MediaControlSlot, at index: Int) {
        guard controlSlots.indices.contains(index) else { return }
        var slots = controlSlots
        slots[index] = slot
        controlSlots = slots
    }

    func resetControlSlots() {
        controlSlots = MediaControlSlot.defaultLayout
    }

    private static func enumValue<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T
    where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }
        return value
    }

    private static func clamped(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }
}
