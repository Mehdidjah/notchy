import SwiftUI

/// Home-tab media player slot (Atoll's MusicPlayerView). Keep this type name and its
/// initialiser: the Home tab creates it.
///
/// Beside the calendar the player shows the current lyric line under the artist; with the
/// calendar off and lyrics on, a lyrics panel sits to the right of the player.
struct HomeMediaSlot: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var settings = MediaSettings.shared
    @ObservedObject private var layout = HomeLayoutState.shared

    var body: some View {
        Group {
            if settings.enableLyrics && !layout.showsCalendar {
                MediaSideLyricsLayout(settings: settings)
            } else {
                MediaPlayerView(showsInlineLyrics: settings.enableLyrics && layout.showsCalendar)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.mediaHoldOpen, holdOpenAction)
        .onAppear { MusicManager.shared.forceRefresh() }
    }

    /// Popovers opened from the player keep the island open while they show.
    private var holdOpenAction: MediaHoldOpenAction {
        let model = model
        return MediaHoldOpenAction { reason, active in
            if active {
                model.holdOpen(reason: reason)
            } else {
                model.releaseHold(reason: reason)
            }
        }
    }
}

/// Artwork on the left, song info, slider and controls on the right.
struct MediaPlayerView: View {
    var showsInlineLyrics: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MediaAlbumArtView(manager: .shared, settings: .shared)
            MediaControlsView(manager: .shared, settings: .shared, showsInlineLyrics: showsInlineLyrics)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Player plus the side lyrics panel, as Atoll's `sideLyricsContent`: the player keeps at
/// least 380 pt, the panel is `lyricsPanelWidth` wide and shifted by `lyricsPanelOffset`.
/// Atoll widens the island to fit; until the host does (`MediaFeature.requiredHomeExtraWidth`)
/// the panel takes what is left, and below 140 pt the inline lyric line is used instead.
private struct MediaSideLyricsLayout: View {
    @ObservedObject var settings: MediaSettings

    static let minimumPlayerWidth: CGFloat = 380
    static let spacing: CGFloat = 20
    static let minimumPanelWidth: CGFloat = 140

    var body: some View {
        GeometryReader { proxy in
            let offset = CGFloat(settings.lyricsPanelOffset)
            let available = proxy.size.width - Self.minimumPlayerWidth - Self.spacing - abs(offset)
            let panelWidth = min(CGFloat(settings.lyricsPanelWidth), available)
            if panelWidth >= Self.minimumPanelWidth {
                HStack(alignment: .top, spacing: Self.spacing) {
                    MediaPlayerView(showsInlineLyrics: false)
                        .frame(minWidth: Self.minimumPlayerWidth, maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    MediaLyricsSidePanel(manager: .shared, settings: settings)
                        .frame(width: panelWidth, alignment: .topLeading)
                        .padding(.leading, max(0, -offset))
                        .offset(x: offset)
                }
            } else {
                MediaPlayerView(showsInlineLyrics: true)
            }
        }
    }
}

// MARK: - Artwork

/// The open artwork: an aspect-fit square as tall as the player, 13-pt continuous corners,
/// a blurred colour glow behind it while playing, a 3D parallax tilt on hover, the source
/// app's icon at the bottom-right, and shrunk to 85 % under a dark veil when paused.
struct MediaAlbumArtView: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings

    /// Atoll inserts the source-app badge once the island is open, popping it in 0.3 s later.
    @State private var showsBadge = false

    private var cornerRadius: CGFloat {
        let base: CGFloat = settings.cornerRadiusScaling ? 13 : 4
        return manager.isArtworkWide ? base / 3 : base
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if settings.lightingEffect {
                glow
            }
            ZStack {
                Button {
                    manager.openMusicApp()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        artwork
                        appIconBadge
                    }
                    .mediaArtworkFlip(angle: manager.flipAngle)
                    .mediaParallax(intensity: settings.parallaxIntensity)
                    .padding(.bottom, -5)
                }
                .buttonStyle(.plain)
                .scaleEffect(manager.isPlaying ? 1 : 0.85)
                .accessibilityHint("Opens \(manager.activeSource?.displayName ?? "Music")")

                Rectangle()
                    .aspectRatio(1, contentMode: .fit)
                    .foregroundStyle(Color.black)
                    .opacity(manager.isPlaying ? 0 : 0.8)
                    .blur(radius: 50)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.bouncy.delay(0.3)) { showsBadge = true }
        }
        .onDisappear { showsBadge = false }
    }

    private var glow: some View {
        GeometryReader { proxy in
            Color.clear
                .background(
                    Image(nsImage: manager.albumArtGlowTexture)
                        .resizable()
                        .aspectRatio(nil, contentMode: .fill)
                )
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .white.opacity(0.7), .clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.65
                    )
                )
                .scaleEffect(x: 1.3, y: 1.4)
                .rotationEffect(.degrees(92))
                .opacity(manager.isPlaying ? 0.5 : 0)
                .shadow(color: manager.avgColor.color.opacity(0.16), radius: 14)
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(nsImage: manager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .mediaMatchedArtwork()
            .clipped()
            .accessibilityLabel("Album art")
    }

    @ViewBuilder
    private var appIconBadge: some View {
        if showsBadge, !manager.usingAppIconForArtwork {
            MediaAppIcon(bundleIdentifier: manager.bundleIdentifier ?? MediaSourceKind.appleMusic.bundleIdentifier)
                .frame(width: 36, height: 36)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                .zIndex(2)
        }
    }
}

// MARK: - Controls

/// Title, artist (tinted), optional lyric line, the progress slider and the control row.
struct MediaControlsView: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings
    var showsInlineLyrics: Bool

    @ObservedObject private var hud = MediaOpenHUDState.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            if hud.isActive {
                MediaControlHUDRow(state: hud)
            } else {
                playbackControls
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tintedColor: Color {
        manager.avgColor.ensuringMinimumBrightness(0.6).color
    }

    private var artistColor: Color {
        settings.playerColorTinting ? tintedColor : .gray
    }

    private var sliderTint: Color {
        switch settings.sliderColor {
        case .white: .white
        case .albumArt: tintedColor
        case .accent: .accentColor
        }
    }

    private var songInfoAndSlider: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: proxy.size.width)
                    .zIndex(1)
                slider
                    .zIndex(0)
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaTitleMarquee(
                text: manager.songTitle,
                isExplicit: manager.isCurrentTrackExplicit,
                font: .headline,
                nsFont: .headline,
                textColor: .white,
                frameWidth: width,
                badgeHeight: 14
            )
            MediaMarqueeText(
                text: manager.artistName,
                font: .headline.weight(.medium),
                nsFont: .headline,
                textColor: artistColor,
                frameWidth: width
            )
            if showsInlineLyrics {
                MediaInlineLyricLine(manager: manager, width: width)
            }
        }
    }

    private var isTimelinePaused: Bool {
        !manager.isPlaying || manager.isLiveStream || manager.playbackRate <= 0
    }

    private var slider: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isTimelinePaused)) { timeline in
            MediaMusicSlider(
                sliderValue: $sliderValue,
                dragging: $dragging,
                lastDragged: $lastDragged,
                duration: manager.songDuration,
                currentDate: timeline.date,
                timestampDate: manager.timestampDate,
                isPlaying: manager.isPlaying,
                isLiveStream: manager.isLiveStream,
                tint: sliderTint,
                labelColor: artistColor,
                position: { manager.estimatedPlaybackPosition(at: $0) },
                onSeek: { manager.seek(to: $0) }
            )
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var displayedSlots: [MediaControlSlot] {
        settings.displayedSlots(canFavorite: manager.canFavorite, isAppleMusicActive: manager.isAppleMusicActive)
    }

    private var repeatIcon: String {
        manager.repeatMode == .one ? "repeat.1" : "repeat"
    }

    @ViewBuilder
    private func slotView(_ slot: MediaControlSlot) -> some View {
        switch slot {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            MediaHoverButton(
                icon: manager.isPlaying ? (manager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
                size: .large,
                accessibilityTitle: manager.isPlaying ? "Pause" : "Play"
            ) {
                manager.togglePlay()
            }
        case .trackBackward:
            MediaHoverButton(
                icon: "backward.fill",
                skipDirection: .backward,
                externalTrigger: pulseToken(direction: .backward, behavior: .track),
                accessibilityTitle: "Previous track"
            ) {
                manager.previousTrack()
            }
        case .trackForward:
            MediaHoverButton(
                icon: "forward.fill",
                skipDirection: .forward,
                externalTrigger: pulseToken(direction: .forward, behavior: .track),
                accessibilityTitle: "Next track"
            ) {
                manager.nextTrack()
            }
        case .seekBackward:
            MediaHoverButton(
                icon: "gobackward.10",
                pressEffect: .wiggle(clockwise: false),
                externalTrigger: pulseToken(direction: .backward, behavior: .tenSecond),
                externalEffect: .wiggle(clockwise: false),
                accessibilityTitle: "Back 10 seconds"
            ) {
                manager.seek(by: -MusicManager.seekInterval)
            }
        case .seekForward:
            MediaHoverButton(
                icon: "goforward.10",
                pressEffect: .wiggle(clockwise: true),
                externalTrigger: pulseToken(direction: .forward, behavior: .tenSecond),
                externalEffect: .wiggle(clockwise: true),
                accessibilityTitle: "Forward 10 seconds"
            ) {
                manager.seek(by: MusicManager.seekInterval)
            }
        case .shuffle:
            MediaHoverButton(
                icon: "shuffle",
                iconColor: manager.isShuffled ? manager.brandAccentColor : .white,
                accessibilityTitle: "Shuffle"
            ) {
                manager.toggleShuffle()
            }
        case .repeatMode:
            MediaHoverButton(
                icon: repeatIcon,
                iconColor: manager.repeatMode == .off ? .white : manager.brandAccentColor,
                accessibilityTitle: "Repeat"
            ) {
                manager.toggleRepeat()
            }
        case .mediaOutput:
            MediaOutputPickerButton()
        case .airPlay:
            MediaAirPlayPickerButton(manager: manager)
        case .lyrics:
            MediaHoverButton(
                icon: settings.enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                iconColor: settings.enableLyrics ? manager.brandAccentColor : .white,
                accessibilityTitle: "Lyrics"
            ) {
                settings.enableLyrics.toggle()
            }
        case .likeTrack:
            MediaHoverButton(
                icon: manager.isCurrentTrackFavorited == true ? "heart.fill" : "heart",
                iconColor: manager.isCurrentTrackFavorited == true ? manager.brandAccentColor : .white,
                accessibilityTitle: "Favorite"
            ) {
                manager.toggleFavorite()
            }
            .opacity(manager.isCurrentTrackFavorited == nil ? 0.4 : 1)
            .disabled(manager.isCurrentTrackFavorited == nil)
        }
    }

    private func pulseToken(direction: MusicManager.SkipDirection, behavior: MediaSkipBehavior) -> Int? {
        guard let pulse = manager.skipPulse, pulse.direction == direction, pulse.behavior == behavior else { return nil }
        return pulse.token
    }
}
