import SwiftUI

/// Home-tab media player card. Keep this type name and its
/// initialiser: the Home tab creates it.
///
/// The current lyric line shows under the title when lyrics are on and no lyrics card sits
/// beside the player.
struct HomeMediaSlot: View {
    @ObservedObject var model: NotchViewModel
    var showsInlineLyrics = false

    var body: some View {
        MediaCardView(manager: .shared, settings: .shared, showsInlineLyrics: showsInlineLyrics)
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

/// The player as a card: the cover fills it under a dark gradient, with a thumbnail, the
/// artist and the album along the top, a favourite button (or the source app's icon) at the
/// top right, and the title, a thin progress bar and the transport controls along the bottom.
/// Without a cover the card keeps its grey face, tinted by the artwork colour.
struct MediaCardView: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings
    var showsInlineLyrics: Bool

    @ObservedObject private var hud = MediaOpenHUDState.shared
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast

    private static let padding = EdgeInsets(top: 10, leading: 12, bottom: 9, trailing: 12)

    private var hasCover: Bool {
        manager.albumArt !== MusicManager.defaultArtwork && !manager.usingAppIconForArtwork
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - Self.padding.leading - Self.padding.trailing)
            ZStack {
                background(size: proxy.size)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 2)
                    titleBlock(width: contentWidth)
                    progress
                        .padding(.top, 3)
                    Group {
                        if hud.isActive {
                            MediaControlHUDRow(state: hud)
                        } else {
                            MediaCardControls(manager: manager, settings: settings)
                        }
                    }
                    .frame(height: 34)
                    .padding(.top, 3)
                }
                .padding(Self.padding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: HomeCardLayout.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Background

    private func background(size: CGSize) -> some View {
        ZStack {
            HomeCardBackground()
            if hasCover {
                Image(nsImage: manager.albumArt)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .black.opacity(0.08), location: 0.32),
                        .init(color: .black.opacity(0.45), location: 0.62),
                        .init(color: .black.opacity(0.8), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [manager.avgColor.color.opacity(0.22), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Color.black
                .opacity(manager.isPlaying ? 0 : 0.3)
                .animation(.smooth(duration: 0.3), value: manager.isPlaying)
        }
        .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { manager.openMusicApp() } label: { thumbnail }
                .accessibilityLabel("Open \(manager.activeSource?.displayName ?? "Music")")
            VStack(alignment: .leading, spacing: 0) {
                Text(manager.artistName)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                Text(albumLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            headerAccessory
        }
    }

    private var albumLine: String {
        let album = manager.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? manager.activeSource?.displayName ?? "" : album
    }

    private var thumbnail: some View {
        Image(nsImage: manager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .mediaArtworkFlip(angle: manager.flipAngle)
            .mediaMatchedArtwork()
    }

    @ViewBuilder
    private var headerAccessory: some View {
        if manager.canFavorite {
            let favorited = manager.isCurrentTrackFavorited == true
            HomeRoundButton(
                symbol: favorited ? "heart.fill" : "heart",
                tint: favorited ? HomeCardPalette.pink : nil,
                diameter: 24,
                glyphSize: 10.5,
                help: favorited ? "Remove from Favorites" : "Favorite"
            ) { manager.toggleFavorite() }
            .opacity(manager.isCurrentTrackFavorited == nil ? 0.45 : 1)
            .disabled(manager.isCurrentTrackFavorited == nil)
        } else {
            MediaAppIcon(bundleIdentifier: manager.bundleIdentifier ?? MediaSourceKind.appleMusic.bundleIdentifier)
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
        }
    }

    // MARK: Title and progress

    private func titleBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaTitleMarquee(
                text: manager.songTitle,
                isExplicit: manager.isCurrentTrackExplicit,
                font: .title3.bold(),
                nsFont: .title3,
                textColor: .white,
                frameWidth: width,
                badgeHeight: 14
            )
            if showsInlineLyrics {
                MediaInlineLyricLine(manager: manager, width: width)
            }
        }
    }

    private var isTimelinePaused: Bool {
        !manager.isPlaying || manager.isLiveStream || manager.playbackRate <= 0
    }

    /// Ticks once a second: the bar moves under a point per second on a card this wide.
    private var progress: some View {
        TimelineView(.animation(minimumInterval: 1, paused: isTimelinePaused)) { timeline in
            MediaMusicSlider(
                sliderValue: $sliderValue,
                dragging: $dragging,
                lastDragged: $lastDragged,
                duration: manager.songDuration,
                currentDate: timeline.date,
                timestampDate: manager.timestampDate,
                isPlaying: manager.isPlaying,
                isLiveStream: manager.isLiveStream,
                tint: .white,
                labelColor: .white.opacity(0.8),
                position: { manager.estimatedPlaybackPosition(at: $0) },
                onSeek: { manager.seek(to: $0) },
                restingTrackHeight: 4,
                draggingTrackHeight: 8,
                labelsAboveTrack: true,
                showsRemainingTime: true,
                labelFontSize: 10
            )
        }
        .frame(height: 22)
    }
}

/// The card's transport row: the player's chosen control slots as round buttons, play/pause
/// larger in the middle. Favouriting lives in the card's header, so its slot is skipped.
private struct MediaCardControls: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings

    private var slots: [MediaControlSlot] {
        settings.displayedSlots(canFavorite: manager.canFavorite, isAppleMusicActive: manager.isAppleMusicActive)
            .filter { $0 != .none && $0 != .likeTrack }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                button(for: slot)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func button(for slot: MediaControlSlot) -> some View {
        switch slot {
        case .playPause:
            HomeRoundButton(
                symbol: manager.isPlaying ? (manager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
                diameter: 34,
                glyphSize: 14,
                help: manager.isPlaying ? "Pause" : "Play"
            ) { manager.togglePlay() }
        case .trackBackward:
            round("backward.fill", help: "Previous track") { manager.previousTrack() }
        case .trackForward:
            round("forward.fill", help: "Next track") { manager.nextTrack() }
        case .seekBackward:
            round("gobackward.10", help: "Back 10 seconds") { manager.seek(by: -MusicManager.seekInterval) }
        case .seekForward:
            round("goforward.10", help: "Forward 10 seconds") { manager.seek(by: MusicManager.seekInterval) }
        case .shuffle:
            round("shuffle", tint: manager.isShuffled ? manager.brandAccentColor : nil, help: "Shuffle") {
                manager.toggleShuffle()
            }
        case .repeatMode:
            round(manager.repeatMode == .one ? "repeat.1" : "repeat",
                  tint: manager.repeatMode == .off ? nil : manager.brandAccentColor,
                  help: "Repeat") { manager.toggleRepeat() }
        case .lyrics:
            round(settings.enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                  tint: settings.enableLyrics ? manager.brandAccentColor : nil,
                  help: "Lyrics") { settings.enableLyrics.toggle() }
        case .mediaOutput:
            MediaOutputPickerButton()
                .scaleEffect(0.85)
                .frame(width: 28, height: 28)
        case .airPlay:
            MediaAirPlayPickerButton(manager: manager)
                .scaleEffect(0.85)
                .frame(width: 28, height: 28)
        case .none, .likeTrack:
            EmptyView()
        }
    }

    private func round(_ symbol: String, tint: Color? = nil, help: String, action: @escaping () -> Void) -> some View {
        HomeRoundButton(symbol: symbol, tint: tint, diameter: 28, glyphSize: 11, help: help, action: action)
    }
}

/// The synced lyrics beside the player, on a card of their own.
struct HomeLyricsCard: View {
    var body: some View {
        HomeCard(padding: EdgeInsets(top: 10, leading: 8, bottom: 6, trailing: 8)) {
            MediaLyricsSidePanel(manager: .shared, settings: .shared)
        }
    }
}
