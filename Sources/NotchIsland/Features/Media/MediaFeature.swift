import Combine
import SwiftUI

/// Entry point of the media feature: starts the music manager, registers the closed-notch
/// music activity and keeps the Home tab's player flag and lyric height in step.
///
/// Host hooks (read-only, all main-actor):
/// - `claimsClosedClick`: a click on the closed notch toggles playback rather than opening it.
/// - `suppressesCloseGesture`: the pointer is over the scrolling lyrics panel.
/// - `sideLyricsRequiredOpenWidth` / `sideLyricsWidthDidChange`: the open width the Home tab
///   needs for Atoll's side lyrics panel.
@MainActor
enum MediaFeature {
    private static var activity: MusicLiveActivity?
    private static var cancellables = Set<AnyCancellable>()
    /// The extra Home height this feature last asked for, so it never clears another
    /// feature's request.
    private static var appliedExtraHeight: CGFloat = 0
    private static let sideLyricsWidth = CurrentValueSubject<CGFloat, Never>(0)

    /// Height of the inline lyric line under the artist (12-pt text plus its 2-pt gap).
    static let inlineLyricsExtraHeight: CGFloat = 18

    /// Atoll's side-lyrics budget: the player's 380 pt, the panel, 20 pt between columns,
    /// the panel's offset and the camera mirror's 220 pt (+20) when shown.
    static let sideLyricsMinimumPlayerWidth: CGFloat = 380
    static let sideLyricsColumnSpacing: CGFloat = 20
    static let sideLyricsMirrorWidth: CGFloat = 220
    /// The Home tab's 8-pt padding plus the open island's 14-pt content insets, each side.
    static let homeContentInsets: CGFloat = 44

    static func start() {
        guard activity == nil else { return }
        let manager = MusicManager.shared
        let settings = MediaSettings.shared
        manager.start()

        let liveActivity = MusicLiveActivity(manager: manager, settings: settings)
        activity = liveActivity
        IslandActivityCenter.shared.register(liveActivity)
        MediaOpenHUDState.shared.start()
        MediaControlWindowController.shared.start()

        let layout = HomeLayoutState.shared
        let triggers: [AnyPublisher<Void, Never>] = [
            manager.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            manager.$songTitle.map { _ in () }.eraseToAnyPublisher(),
            manager.$artistName.map { _ in () }.eraseToAnyPublisher(),
            settings.$showStandardMediaControls.map { _ in () }.eraseToAnyPublisher(),
            settings.$autoHideInactivePlayer.map { _ in () }.eraseToAnyPublisher(),
            settings.$enableLyrics.map { _ in () }.eraseToAnyPublisher(),
            settings.$lyricsPanelWidth.map { _ in () }.eraseToAnyPublisher(),
            settings.$lyricsPanelOffset.map { _ in () }.eraseToAnyPublisher(),
            layout.$showsCalendar.map { _ in () }.eraseToAnyPublisher(),
            layout.$showsMirror.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(triggers)
            .receive(on: RunLoop.main)
            .sink { updateHomeLayout() }
            .store(in: &cancellables)
        updateHomeLayout()
    }

    static func stop() {
        guard activity != nil else { return }
        cancellables.removeAll()
        IslandActivityCenter.shared.unregister(id: "media.music")
        activity = nil
        MediaControlWindowController.shared.stop()
        MediaOpenHUDState.shared.stop()
        MediaAudioRouteManager.shared.stop()
        MusicManager.shared.stop()
        let interaction = MediaInteractionState.shared
        interaction.setClaimsClosedClick(false)
        interaction.setSuppressesCloseGesture(false)
        interaction.setClosedWings(nil)
        let layout = HomeLayoutState.shared
        if layout.showsMediaPlayer { layout.showsMediaPlayer = false }
        if appliedExtraHeight != 0 {
            layout.extraHeight = max(0, layout.extraHeight - appliedExtraHeight)
            appliedExtraHeight = 0
        }
        if sideLyricsWidth.value != 0 { sideLyricsWidth.send(0) }
    }

    // MARK: - Host hooks

    /// True while the pointer is on the closed spectrum showing its play/pause glyph: the
    /// click belongs to the media feature and must not open the island.
    static var claimsClosedClick: Bool { MediaInteractionState.shared.claimsClosedClick }

    /// True while the pointer is over the side lyrics panel: scrolling there must not count
    /// as a swipe to close the island.
    static var suppressesCloseGesture: Bool { MediaInteractionState.shared.suppressesCloseGesture }

    /// The open width (the host's `openNotchWidth` scale) the Home tab needs for the side
    /// lyrics panel, or 0 when the panel is not shown.
    static var sideLyricsRequiredOpenWidth: CGFloat { sideLyricsWidth.value }

    /// Emits whenever `sideLyricsRequiredOpenWidth` changes.
    static var sideLyricsWidthDidChange: AnyPublisher<CGFloat, Never> {
        sideLyricsWidth.removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: - Layout

    /// Atoll: the player shows when media controls are on and either auto-hide is off or a
    /// session is active; the inline lyric line needs 18 pt more beside the calendar.
    static func shouldShowPlayer(settings: MediaSettings, hasActiveSession: Bool) -> Bool {
        settings.showStandardMediaControls && (!settings.autoHideInactivePlayer || hasActiveSession)
    }

    /// Atoll's `sideLyricsRequiredNotchWidth`, in NotchIsland's insets.
    static func sideLyricsRequiredOpenWidth(
        showsPlayer: Bool,
        lyricsEnabled: Bool,
        showsCalendar: Bool,
        showsMirror: Bool,
        panelWidth: CGFloat,
        panelOffset: CGFloat
    ) -> CGFloat {
        guard showsPlayer, lyricsEnabled, !showsCalendar else { return 0 }
        let mirror = showsMirror ? sideLyricsMirrorWidth + sideLyricsColumnSpacing : 0
        return sideLyricsMinimumPlayerWidth + max(0, panelWidth) + sideLyricsColumnSpacing
            + abs(panelOffset) + mirror + homeContentInsets
    }

    private static func updateHomeLayout() {
        let manager = MusicManager.shared
        let settings = MediaSettings.shared
        let layout = HomeLayoutState.shared

        let showsPlayer = shouldShowPlayer(settings: settings, hasActiveSession: manager.hasActiveSession)
        if layout.showsMediaPlayer != showsPlayer {
            layout.showsMediaPlayer = showsPlayer
        }

        let wantedExtra = showsPlayer && settings.enableLyrics && layout.showsCalendar ? inlineLyricsExtraHeight : 0
        if wantedExtra != appliedExtraHeight {
            layout.extraHeight = max(0, layout.extraHeight - appliedExtraHeight + wantedExtra)
            appliedExtraHeight = wantedExtra
        }

        let width = sideLyricsRequiredOpenWidth(
            showsPlayer: showsPlayer,
            lyricsEnabled: settings.enableLyrics,
            showsCalendar: layout.showsCalendar,
            showsMirror: layout.showsMirror,
            panelWidth: CGFloat(settings.lyricsPanelWidth),
            panelOffset: CGFloat(settings.lyricsPanelOffset)
        )
        if sideLyricsWidth.value != width { sideLyricsWidth.send(width) }
    }
}
