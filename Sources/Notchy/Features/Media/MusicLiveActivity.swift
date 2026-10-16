import AppKit
import Combine
import SwiftUI

/// The island-wide preferences the media views follow, read from the host's
/// UserDefaults keys ("notch.openOnHover", "notch.hapticsEnabled", both default on).
enum MediaHostPreferences {
    static var opensOnHover: Bool {
        UserDefaults.standard.object(forKey: "notch.openOnHover") as? Bool ?? true
    }

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notch.hapticsEnabled") as? Bool ?? true
    }
}

/// Closed-notch wing geometry shared by the activity and the tests.
enum MediaClosedLayout {
    /// The artwork is `closedHeight - 12` square, never wider than the wing.
    static func artworkSize(in context: ClosedActivityContext) -> CGFloat {
        min(max(0, context.closedHeight - 12), context.wingBaseWidth)
    }

    /// 4 pt corners, a third of that for landscape artwork.
    static func artworkCornerRadius(isWide: Bool) -> CGFloat {
        isWide ? 4.0 / 3.0 : 4
    }

    /// The closed centre widens to 380 pt while the inline sneak peek shows.
    static let inlinePeekCenterWidth: CGFloat = 380

    /// Width of each text column beside the notch during the inline peek.
    static func inlinePeekColumnWidth(centerWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        max(0, (centerWidth - notchWidth) / 2 - 12)
    }

    /// Whether the activity wants the closed notch (pairing eligibility, minus the
    /// lock-screen and hide-on-closed gates the host owns).
    static func isEligible(
        liveActivityEnabled: Bool,
        showsStandardControls: Bool,
        isPlaying: Bool,
        isPlayerIdle: Bool,
        title: String,
        artist: String
    ) -> Bool {
        let hasSnapshot = isPlaying || (!isPlayerIdle && MediaPlaceholder.hasRealMetadata(title: title, artist: artist))
        return liveActivityEnabled && showsStandardControls && hasSnapshot
    }
}

/// The music live activity: album art in the left wing, the spectrum in the right wing,
/// optionally "title • artist" over the centre on displays without a camera housing.
@MainActor
final class MusicLiveActivity: ClosedLiveActivity {
    let activityID = "media.music"
    let priority = ClosedActivityPriority.music

    private let manager: MusicManager
    private let settings: MediaSettings
    private let changes = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private(set) var isActivityVisible = false
    private var showsCenterMetadata = false
    private var widensForInlinePeek = false

    var activityDidChange: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    init(manager: MusicManager, settings: MediaSettings) {
        self.manager = manager
        self.settings = settings

        let triggers: [AnyPublisher<Void, Never>] = [
            manager.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            manager.$isPlayerIdle.map { _ in () }.eraseToAnyPublisher(),
            manager.$songTitle.map { _ in () }.eraseToAnyPublisher(),
            manager.$artistName.map { _ in () }.eraseToAnyPublisher(),
            settings.$liveActivityEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$showStandardMediaControls.map { _ in () }.eraseToAnyPublisher(),
            settings.$showSongMetadataInClosedNotch.map { _ in () }.eraseToAnyPublisher(),
            manager.$isInlinePeekActive.map { _ in () }.eraseToAnyPublisher(),
            settings.$enableSneakPeek.map { _ in () }.eraseToAnyPublisher(),
            settings.$sneakPeekStyle.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(triggers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.recompute() }
            .store(in: &cancellables)
        recompute()
    }

    private func recompute() {
        let visible = MediaClosedLayout.isEligible(
            liveActivityEnabled: settings.liveActivityEnabled,
            showsStandardControls: settings.showStandardMediaControls,
            isPlaying: manager.isPlaying,
            isPlayerIdle: manager.isPlayerIdle,
            title: manager.songTitle,
            artist: manager.artistName
        )
        let center = settings.showSongMetadataInClosedNotch
        let widens = manager.isInlinePeekActive && settings.enableSneakPeek && settings.sneakPeekStyle == .inline
        guard visible != isActivityVisible || center != showsCenterMetadata || widens != widensForInlinePeek else { return }
        isActivityVisible = visible
        showsCenterMetadata = center
        widensForInlinePeek = widens
        changes.send()
    }

    /// The closed centre is 380 pt wide while the inline sneak peek shows. Picked up by the
    /// host's layout once `ClosedLiveActivity` carries a centre-width override.
    func centerWidthOverride(in context: ClosedActivityContext) -> CGFloat? {
        widensForInlinePeek ? MediaClosedLayout.inlinePeekCenterWidth : nil
    }

    func leftWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(MediaClosedArtworkWing(manager: manager, context: context))
    }

    func rightWing(in context: ClosedActivityContext) -> AnyView {
        AnyView(MediaClosedSpectrumWing(manager: manager, settings: settings))
    }

    func centerOverlay(in context: ClosedActivityContext) -> AnyView? {
        AnyView(MediaClosedCenterOverlay(manager: manager, settings: settings, context: context))
    }
}

/// Left wing: the artwork square with the flip, centred in the wing.
struct MediaClosedArtworkWing: View {
    @ObservedObject var manager: MusicManager
    let context: ClosedActivityContext

    var body: some View {
        let side = MediaClosedLayout.artworkSize(in: context)
        Color.clear
            .frame(width: side, height: side)
            .background(
                Image(nsImage: manager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: MediaClosedLayout.artworkCornerRadius(isWide: manager.isArtworkWide)))
            )
            .clipped()
            .mediaMatchedArtwork()
            .mediaArtworkFlip(angle: manager.flipAngle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Album art")
            .background(MediaScreenReader { frame in
                screenFrame = frame
                publishWings()
            })
            .onAppear(perform: publishWings)
            .onChange(of: context) { _, _ in publishWings() }
            .onDisappear { MediaInteractionState.shared.setClosedWings(nil) }
    }

    @State private var screenFrame: NSRect?

    /// Tells the floating controls where the closed wings are.
    private func publishWings() {
        guard let screenFrame else { return }
        MediaInteractionState.shared.setClosedWings(.init(
            screenFrame: screenFrame,
            closedHeight: context.closedHeight,
            centerWidth: context.centerWidth,
            wingWidth: context.wingBaseWidth
        ))
    }
}

/// Right wing: the spectrum. With "open on hover" off, hovering blurs it under a play/pause
/// glyph and a click toggles playback with a haptic.
struct MediaClosedSpectrumWing: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings
    @State private var isHovering = false

    /// The host's "notch.openOnHover" preference.
    private var opensOnHover: Bool {
        MediaHostPreferences.opensOnHover
    }

    var body: some View {
        let overlayEnabled = !opensOnHover
        MediaSpectrumWing(manager: manager, settings: settings)
            .blur(radius: overlayEnabled && isHovering ? 2.4 : 0)
            .overlay {
                if overlayEnabled {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(isHovering ? 0.24 : 0.02))
                        Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(isHovering ? 0.98 : 0))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !opensOnHover else {
                    if isHovering { isHovering = false }
                    MediaInteractionState.shared.setClaimsClosedClick(false)
                    return
                }
                withAnimation(.smooth(duration: 0.16)) {
                    isHovering = hovering
                }
                MediaInteractionState.shared.setClaimsClosedClick(hovering)
            }
            .onDisappear {
                isHovering = false
                MediaInteractionState.shared.setClaimsClosedClick(false)
            }
            .modifier(MediaClosedTapToggle(enabled: overlayEnabled && isHovering, manager: manager))
            .animation(.smooth(duration: 0.16), value: isHovering)
            .animation(.smooth(duration: 0.2), value: manager.isPlaying)
    }
}

/// Only claims the click when the play/pause overlay is showing, so elsewhere a click still
/// reaches the island and opens it.
private struct MediaClosedTapToggle: ViewModifier {
    let enabled: Bool
    let manager: MusicManager

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture {
                if MediaHostPreferences.hapticsEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                manager.togglePlay()
            }
        } else {
            content
        }
    }
}

/// What is drawn over the black centre: the inline sneak peek (title marquee on the left
/// of the notch, artist on the right) or, on displays without a camera housing, an optional
/// "Title • Artist" marquee.
struct MediaClosedCenterOverlay: View {
    @ObservedObject var manager: MusicManager
    @ObservedObject var settings: MediaSettings
    let context: ClosedActivityContext

    private var textColor: Color {
        settings.coloredSpectrogram ? manager.avgColor.color : .gray
    }

    private var showsInlinePeek: Bool {
        manager.isInlinePeekActive && settings.enableSneakPeek && settings.sneakPeekStyle == .inline
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(alignment: .top) {
                // The inline peek needs room either side of the camera; until the island
                // has widened, nothing is drawn behind the hardware notch.
                if showsInlinePeek, width > context.notchWidth + 24 {
                    MediaTitleMarquee(
                        text: manager.songTitle,
                        isExplicit: manager.isCurrentTrackExplicit,
                        textColor: textColor,
                        minDuration: 0.4,
                        frameWidth: MediaClosedLayout.inlinePeekColumnWidth(centerWidth: width, notchWidth: context.notchWidth),
                        badgeHeight: 13
                    )
                    .padding(.leading, 8)
                    Spacer(minLength: context.notchWidth)
                    Text(manager.artistName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(textColor)
                        .padding(.trailing, 8)
                } else if settings.showSongMetadataInClosedNotch, !context.hasHardwareNotch, !manager.songTitle.isEmpty {
                    MediaMarqueeText(
                        text: "\(manager.songTitle) • \(manager.artistName)",
                        textColor: textColor,
                        minDuration: 3,
                        frameWidth: max(0, width - 16)
                    )
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}
