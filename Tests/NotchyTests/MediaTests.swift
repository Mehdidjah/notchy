import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Notchy

@MainActor
struct MediaTests {
    // MARK: Playback math

    @Test
    func estimatedPositionExtrapolatesWhilePlayingAndClampsToDuration() {
        let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
        let playing = MediaPlaybackMath.estimatedPosition(
            elapsed: 30, anchor: anchor, rate: 1, isPlaying: true, duration: 200, at: anchor.addingTimeInterval(2.5))
        #expect(playing == 32.5)

        let clamped = MediaPlaybackMath.estimatedPosition(
            elapsed: 199, anchor: anchor, rate: 1, isPlaying: true, duration: 200, at: anchor.addingTimeInterval(10))
        #expect(clamped == 200)

        let paused = MediaPlaybackMath.estimatedPosition(
            elapsed: 30, anchor: anchor, rate: 1, isPlaying: false, duration: 200, at: anchor.addingTimeInterval(60))
        #expect(paused == 30, "a paused track does not move")
    }

    @Test
    func timeStringFormatsMinutesHoursAndRejectsNonTimes() {
        #expect(MediaPlaybackMath.timeString(0) == "0:00")
        #expect(MediaPlaybackMath.timeString(185.9) == "3:05")
        #expect(MediaPlaybackMath.timeString(3_723) == "1:02:03")
        #expect(MediaPlaybackMath.timeString(.nan) == "--:--")
        #expect(MediaPlaybackMath.timeString(-1) == "--:--")
        #expect(MediaPlaybackMath.isUsableDuration(240))
        #expect(!MediaPlaybackMath.isUsableDuration(0))
        #expect(!MediaPlaybackMath.isUsableDuration(1_732_919_508), "epoch-like durations are not track lengths")
    }

    // MARK: Session rules

    @Test
    func placeholderMetadataNeverCountsAsASession() {
        #expect(!MediaPlaceholder.hasActiveSession(isPlaying: false, title: "I'm Handsome", artist: "Me"))
        #expect(!MediaPlaceholder.hasActiveSession(isPlaying: false, title: "Not Playing", artist: "Unknown"))
        #expect(MediaPlaceholder.hasActiveSession(isPlaying: true, title: "Not Playing", artist: "Unknown"))
        #expect(MediaPlaceholder.hasActiveSession(isPlaying: false, title: "Halo", artist: "Beyoncé"))
    }

    @Test
    func closedActivityShowsWhilePlayingOrPausedButNotIdle() {
        func eligible(playing: Bool, idle: Bool, enabled: Bool = true, controls: Bool = true) -> Bool {
            MediaClosedLayout.isEligible(
                liveActivityEnabled: enabled, showsStandardControls: controls,
                isPlaying: playing, isPlayerIdle: idle, title: "Halo", artist: "Beyoncé")
        }
        #expect(eligible(playing: true, idle: true))
        #expect(eligible(playing: false, idle: false))
        #expect(!eligible(playing: false, idle: true))
        #expect(!eligible(playing: true, idle: false, enabled: false))
        #expect(!eligible(playing: true, idle: false, controls: false))
    }

    @Test
    func closedArtworkIsTwelvePointsShortOfTheNotchAndFitsTheWing() {
        let resting = ClosedActivityContext(closedHeight: 32, notchWidth: 190, isHovering: false, gestureProgress: 0, hasHardwareNotch: true)
        #expect(MediaClosedLayout.artworkSize(in: resting) == 20)
        #expect(resting.wingBaseWidth == 20)

        let hovered = ClosedActivityContext(closedHeight: 32, notchWidth: 190, isHovering: true, gestureProgress: 0, hasHardwareNotch: true)
        #expect(MediaClosedLayout.artworkSize(in: hovered) == 20, "hover widens the wing, not the artwork")
        #expect(hovered.wingBaseWidth == 32)
        #expect(MediaClosedLayout.artworkCornerRadius(isWide: false) == 4)
        #expect(MediaSpectrumBars.width(for: 4) == 16)
        #expect(MediaSpectrumBars.width(for: 6) == 24)
    }

    @Test
    func playerVisibilityFollowsAutoHide() {
        let settings = MediaSettings(defaults: Self.makeDefaults())
        #expect(!MediaFeature.shouldShowPlayer(settings: settings, hasActiveSession: false))
        #expect(MediaFeature.shouldShowPlayer(settings: settings, hasActiveSession: true))
        settings.autoHideInactivePlayer = false
        #expect(MediaFeature.shouldShowPlayer(settings: settings, hasActiveSession: false))
        settings.showStandardMediaControls = false
        #expect(!MediaFeature.shouldShowPlayer(settings: settings, hasActiveSession: true))
    }

    @Test
    func optimisticToggleIgnoresContradictingEventsUntilConfirmed() {
        var optimistic = MediaOptimisticPlayback()
        optimistic.begin(expecting: true)
        let stale = optimistic.shouldApply(eventIsPlaying: false)
        #expect(!stale, "a stale paused reading is ignored")
        let confirmed = optimistic.shouldApply(eventIsPlaying: true)
        #expect(confirmed)
        #expect(optimistic.expectedState == nil)
        let later = optimistic.shouldApply(eventIsPlaying: false)
        #expect(later, "after confirmation every event applies")

        optimistic.begin(expecting: false)
        let wrongCancel = optimistic.cancel(ifExpecting: true)
        #expect(!wrongCancel)
        let rightCancel = optimistic.cancel(ifExpecting: false)
        #expect(rightCancel)
    }

    @Test
    func liveStreamDetectedAfterThreeReadingsWithoutDuration() {
        var detector = MediaLiveStreamDetector()
        detector.observe(isPlaying: true, position: 5, duration: 0)
        detector.observe(isPlaying: true, position: 6, duration: 0)
        #expect(!detector.isLive)
        detector.observe(isPlaying: true, position: 7, duration: 0)
        #expect(detector.isLive)
        detector.observe(isPlaying: true, position: 20, duration: 240)
        #expect(!detector.isLive, "a real duration with time remaining clears it")
    }

    // MARK: Settings

    @Test
    func settingsUseDesignDefaults() {
        let settings = MediaSettings(defaults: Self.makeDefaults())
        #expect(settings.sourcePreference == .automatic)
        #expect(settings.waitInterval == 3)
        #expect(settings.showStandardMediaControls)
        #expect(settings.autoHideInactivePlayer)
        #expect(settings.customizableControls)
        #expect(settings.controlSlots == [.shuffle, .trackBackward, .playPause, .trackForward, .repeatMode])
        #expect(settings.skipBehavior == .track)
        #expect(settings.liveActivityEnabled)
        #expect(!settings.enableSneakPeek)
        #expect(settings.sneakPeekOnTrackChange)
        #expect(!settings.enableLyrics)
        #expect(settings.lyricsPanelWidth == 280)
        #expect(settings.parallaxIntensity == 6)
        #expect(!settings.showSongMetadataInClosedNotch)
        #expect(settings.useMusicVisualizer)
        #expect(settings.visualizerBarCount == 4)
        #expect(settings.coloredSpectrogram)
        #expect(settings.colorExtractionMode == .vibrant)
        #expect(settings.playerColorTinting)
        #expect(settings.sliderColor == .white)
        #expect(settings.lightingEffect)
        #expect(settings.cornerRadiusScaling)
    }

    @Test
    func settingsPersistUnderMediaKeys() {
        let defaults = Self.makeDefaults()
        let settings = MediaSettings(defaults: defaults)
        settings.sourcePreference = .spotify
        settings.visualizerBarCount = 6
        settings.enableLyrics = true
        settings.setSlot(.likeTrack, at: 4)

        #expect(defaults.string(forKey: "media.sourcePreference") == "spotify")
        let reloaded = MediaSettings(defaults: defaults)
        #expect(reloaded.sourcePreference == .spotify)
        #expect(reloaded.visualizerBarCount == 6)
        #expect(reloaded.enableLyrics)
        #expect(reloaded.controlSlots.last == .likeTrack)
    }

    @Test
    func displayedSlotsFollowDesignLayouts() {
        let settings = MediaSettings(defaults: Self.makeDefaults())
        settings.setSlot(.likeTrack, at: 0)
        #expect(settings.displayedSlots(canFavorite: false).first == MediaControlSlot.none)
        #expect(settings.displayedSlots(canFavorite: true).first == .likeTrack)

        settings.controlSlots = Array(repeating: .none, count: 5)
        #expect(settings.displayedSlots(canFavorite: true) == MediaControlSlot.defaultLayout, "an empty layout falls back")

        settings.customizableControls = false
        #expect(settings.displayedSlots(canFavorite: true) == [.none, .trackBackward, .playPause, .trackForward, .none])
        settings.skipBehavior = .tenSecond
        #expect(settings.displayedSlots(canFavorite: true) == [.none, .seekBackward, .playPause, .seekForward, .none])
    }

    // MARK: AppleScript replies

    @Test
    func parsesMusicReply() throws {
        let reply = NSAppleEventDescriptor.list()
        reply.insert(NSAppleEventDescriptor(boolean: true), at: 1)
        reply.insert(NSAppleEventDescriptor(string: "Halo"), at: 2)
        reply.insert(NSAppleEventDescriptor(string: "Beyoncé"), at: 3)
        reply.insert(NSAppleEventDescriptor(string: "I Am... Sasha Fierce"), at: 4)
        reply.insert(NSAppleEventDescriptor(double: 42.5), at: 5)
        reply.insert(NSAppleEventDescriptor(double: 261.0), at: 6)
        reply.insert(NSAppleEventDescriptor(boolean: false), at: 7)
        reply.insert(NSAppleEventDescriptor(int32: 2), at: 8)
        reply.insert(NSAppleEventDescriptor(string: "ABCDEF0123"), at: 9)

        let date = Date()
        let snapshot = try #require(MediaScripting.parseAppleMusic(reply, at: date))
        #expect(snapshot.source == .appleMusic)
        #expect(snapshot.isPlaying)
        #expect(snapshot.title == "Halo")
        #expect(snapshot.position == 42.5)
        #expect(snapshot.duration == 261)
        #expect(snapshot.repeatMode == .one)
        #expect(snapshot.trackIdentifier == "ABCDEF0123")
        #expect(snapshot.lastUpdated == date)
    }

    @Test
    func parsesSpotifyReplyWithMillisecondDuration() throws {
        let reply = NSAppleEventDescriptor.list()
        let values: [NSAppleEventDescriptor] = [
            NSAppleEventDescriptor(boolean: false),
            NSAppleEventDescriptor(string: "Song"),
            NSAppleEventDescriptor(string: "Artist"),
            NSAppleEventDescriptor(string: "Album"),
            NSAppleEventDescriptor(double: 12),
            NSAppleEventDescriptor(double: 215_000),
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(boolean: true),
            NSAppleEventDescriptor(string: "https://i.scdn.co/image/abc"),
            NSAppleEventDescriptor(string: "spotify:track:123"),
            NSAppleEventDescriptor(string: "https://open.spotify.com/track/123")
        ]
        for (index, value) in values.enumerated() {
            reply.insert(value, at: index + 1)
        }
        let snapshot = try #require(MediaScripting.parseSpotify(reply, at: Date()))
        #expect(snapshot.duration == 215)
        #expect(snapshot.isShuffled)
        #expect(snapshot.repeatMode == .all)
        #expect(snapshot.artworkURL == "https://i.scdn.co/image/abc")
        #expect(snapshot.artworkKey == "spotify|spotify:track:123")
    }

    @Test
    func commandScriptsNeverDependOnLocaleAndCycleRepeat() {
        #expect(MediaScripting.script(for: .seek(83.25), on: .appleMusic) == "tell application \"Music\" to set player position to 83.250")
        #expect(MediaScripting.script(for: .toggleShuffle, on: .spotify) == "tell application \"Spotify\" to set shuffling to not shuffling")
        #expect(MediaScripting.script(for: .cycleRepeat, on: .appleMusic).contains("set song repeat to all"))
        #expect(MediaScripting.script(for: .nextTrack, on: .spotify) == "tell application \"Spotify\" to next track")
    }

    // MARK: Lyrics

    @Test
    func lrcParserHandlesRepeatsFractionsAndOffset() {
        let lrc = """
        [offset:+500]
        [00:12.5]First
        [00:20.50][01:00.500]Chorus
        [00:30]
        not a lyric
        """
        let lines = MediaLyricsEngine.parseLRC(lrc)
        #expect(lines.count == 4)
        #expect(lines[0] == MediaLyricLine(timestamp: 12, text: "First"))
        #expect(lines[1] == MediaLyricLine(timestamp: 20, text: "Chorus"))
        #expect(lines[2] == MediaLyricLine(timestamp: 29.5, text: ""), "a bare tag marks where singing stops")
        #expect(lines[3] == MediaLyricLine(timestamp: 60, text: "Chorus"))
    }

    @Test
    func currentLineSweepAndInstrumentalBreaks() {
        let lines = [
            MediaLyricLine(timestamp: 8, text: "One"),
            MediaLyricLine(timestamp: 12, text: ""),
            MediaLyricLine(timestamp: 20, text: "Two")
        ]
        #expect(MediaLyricsEngine.currentIndex(in: lines, at: 3) == -1)
        #expect(MediaLyricsEngine.currentIndex(in: lines, at: 9) == 0)
        #expect(MediaLyricsEngine.sweepProgress(in: lines, index: 0, position: 10, duration: 60) == 0.5)
        #expect(MediaLyricsEngine.isInstrumentalBreak(lines: lines, index: -1, duration: 60), "an 8 s intro is a break")
        #expect(MediaLyricsEngine.isInstrumentalBreak(lines: lines, index: 1, duration: 60))
        #expect(!MediaLyricsEngine.isInstrumentalBreak(lines: lines, index: 0, duration: 60))
        #expect(MediaLyricsEngine.delayUntilNextLine(in: lines, after: 7.99) == 0.05)
        #expect(MediaLyricsEngine.delayUntilNextLine(in: lines, after: 0) == 0.25)
    }

    @Test
    func titleCleanupAndPlaceholderTracks() {
        #expect(MediaLyricsEngine.normalizedTitle("Crimewave (feat. Someone)") == "Crimewave")
        #expect(MediaLyricsEngine.normalizedTitle("Song - 2011 Remaster") == "Song - 2011 Remaster")
        #expect(MediaLyricsEngine.normalizedTitle("Song (Remastered 2011)") == "Song")
        #expect(MediaLyricsEngine.normalizedTitle("Hit  -  ft. Guest") == "Hit")
        #expect(MediaLyricsEngine.namesNoParticularTrack(title: "Track 3", artist: "Band"))
        #expect(MediaLyricsEngine.namesNoParticularTrack(title: "Song", artist: "Unknown Artist"))
        #expect(MediaLyricsEngine.namesNoParticularTrack(title: "I'm Handsome", artist: "Me"))
        #expect(!MediaLyricsEngine.namesNoParticularTrack(title: "Untitled", artist: "Band"))
    }

    @Test
    func lrclibMatchingRequiresAgreementAndPrefersSyncedLyrics() {
        typealias Candidate = MediaLyricsEngine.Candidate
        let wrongArtist = Candidate(trackName: "Halo", artistName: "Someone Else", albumName: "I Am", syncedLyrics: "[00:01]x")
        let karaoke = Candidate(trackName: "Halo (Karaoke Version)", artistName: "Beyonce", syncedLyrics: "[00:01]x")
        let plainExact = Candidate(trackName: "Halo", artistName: "Beyoncé", albumName: "I Am... Sasha Fierce", plainLyrics: "words")
        let syncedLoose = Candidate(trackName: "Halo", artistName: "Beyonce feat. X", syncedLyrics: "[00:01]words")

        let best = MediaLyricsEngine.bestMatch(
            in: [wrongArtist, karaoke, plainExact, syncedLoose],
            title: "Halo", artist: "Beyonce", album: "I Am... Sasha Fierce", duration: 261)
        #expect(best == syncedLoose, "timings win over a better-scored untimed row; diacritics fold on both sides")

        let none = MediaLyricsEngine.bestMatch(in: [wrongArtist, karaoke], title: "Halo", artist: "Beyonce", album: "", duration: 0)
        #expect(none == nil, "nothing agreeing on title and artist is accepted")

        let instrumental = Candidate(trackName: "Halo", artistName: "Beyonce", duration: 76, instrumental: true)
        #expect(MediaLyricsEngine.bestMatch(in: [instrumental], title: "Halo", artist: "Beyonce", album: "", duration: 261) == nil)
    }

    @Test
    func lyricsResolutionPrefersTimedLines() {
        let synced = MediaLyricsEngine.Candidate(plainLyrics: "Hello\nWorld", syncedLyrics: "[00:01.00]Hello\n[00:03.00]World")
        #expect(MediaLyricsEngine.resolution(for: synced).availability == .timed)
        let plain = MediaLyricsEngine.Candidate(plainLyrics: "Hello\n\nWorld")
        let resolution = MediaLyricsEngine.resolution(for: plain)
        #expect(resolution.availability == .untimed)
        #expect(resolution.lines.map(\.text) == ["Hello", "World"])
        #expect(resolution.lines.allSatisfy { !$0.isTimed })
    }

    // MARK: Artwork

    @Test
    func minimumBrightnessLiftsDarkTintsToTheTargetLuminance() {
        let dark = MediaRGB(red: 0.1, green: 0.05, blue: 0.2)
        let lifted = dark.ensuringMinimumBrightness(0.6)
        #expect(abs(lifted.luminance - 0.6) < 0.05 || lifted.red == 1 || lifted.green == 1 || lifted.blue == 1)
        #expect(lifted.luminance > dark.luminance)
        #expect(MediaRGB(red: 0, green: 0, blue: 0).ensuringMinimumBrightness(0.6) == MediaRGB(red: 0.6, green: 0.6, blue: 0.6))
    }

    @Test
    func artworkAnalysisFindsTheDominantHueAndLiftsNearBlack() throws {
        let red = try #require(Self.solidImage(red: 0.9, green: 0.1, blue: 0.1))
        let analysis = MediaArtworkProcessing.analyze(cgImage: red, mode: .vibrant)
        #expect(analysis.primary.red > analysis.primary.green)
        #expect(analysis.primary.red > analysis.primary.blue)
        #expect(!analysis.isWide)

        let black = try #require(Self.solidImage(red: 0, green: 0, blue: 0))
        #expect(MediaArtworkProcessing.quickAverageColor(black) == MediaRGB(red: 0.5, green: 0.5, blue: 0.5))
    }

    @Test
    func explicitMatchScoringNeedsTitleAndArtist() {
        let track = MediaArtworkResolver.SearchTrack(
            trackName: "Halo", artistName: "Beyoncé", collectionName: "I Am... Sasha Fierce", artworkUrl100: nil, trackExplicitness: "notExplicit")
        #expect(MediaArtworkResolver.explicitMatchScore(track, title: "Halo", artist: "Beyonce", album: "I Am... Sasha Fierce") == 12)
        #expect(MediaArtworkResolver.explicitMatchScore(track, title: "Other", artist: "Beyonce", album: "") == Int.min)
        #expect(MediaArtworkResolver.canonicalTitle("Halo (Live) - 2009 Remaster") == "halo")
    }

    @Test
    func sneakPeekTextIsTitleDashArtist() {
        #expect(MusicManager.sneakPeekText(title: "Halo", artist: "Beyoncé") == "Halo - Beyoncé")
    }

    // MARK: Parity additions

    @Test
    func newSettingsUseDesignDefaultsAndPersist() {
        let defaults = Self.makeDefaults()
        let settings = MediaSettings(defaults: defaults)
        #expect(settings.showMediaOutputControl)
        #expect(!settings.reverseSwipeGestures)
        #expect(settings.lyricHighlightStyle == .sweep)
        #expect(settings.lyricsPanelOffset == 0)
        #expect(settings.sneakPeekStyle == .standard)
        #expect(!settings.controlWindowEnabled)

        settings.lyricHighlightStyle = .gradient
        settings.sneakPeekStyle = .inline
        settings.lyricsPanelOffset = -40
        settings.reverseSwipeGestures = true
        let reloaded = MediaSettings(defaults: defaults)
        #expect(reloaded.lyricHighlightStyle == .gradient)
        #expect(reloaded.sneakPeekStyle == .inline)
        #expect(reloaded.lyricsPanelOffset == -40)
        #expect(reloaded.reverseSwipeGestures)
        #expect(defaults.string(forKey: "media.sneakPeekStyle") == "inline")
    }

    @Test
    func outputAndAirPlaySlotsFollowNormalisation() {
        let slots: [MediaControlSlot] = [.mediaOutput, .trackBackward, .playPause, .airPlay, .likeTrack]
        #expect(slots.normalizedSlots(canFavorite: true, allowsMediaOutput: true, isAppleMusicActive: true) == slots)
        #expect(slots.normalizedSlots(canFavorite: true, allowsMediaOutput: false, isAppleMusicActive: true).first == MediaControlSlot.none)
        #expect(slots.normalizedSlots(canFavorite: false, allowsMediaOutput: true, isAppleMusicActive: false)
            == [.mediaOutput, .trackBackward, .playPause, .none, .none], "AirPlay is Music-only")
        #expect(MediaControlSlot.pickerOptions.suffix(3) == [.mediaOutput, .airPlay, .none])
        #expect(MediaControlSlot.mediaOutput.label == "Change Media Output")
        #expect(MediaControlSlot.airPlay.iconName == "airplayaudio")

        let settings = MediaSettings(defaults: Self.makeDefaults())
        settings.setSlot(.airPlay, at: 0)
        #expect(settings.displayedSlots(canFavorite: true, isAppleMusicActive: false).first == MediaControlSlot.none)
        #expect(settings.displayedSlots(canFavorite: true, isAppleMusicActive: true).first == .airPlay)
    }

    @Test
    func outputDeviceGlyphsAndOrderMatchDesign() {
        #expect(MediaAudioOutputDevice.iconName(name: "Mehdi's AirPods Pro", transportType: 0) == "airpodspro")
        #expect(MediaAudioOutputDevice.iconName(name: "MacBook Pro Speakers", transportType: 0) == "laptopcomputer")
        #expect(MediaAudioOutputDevice.iconName(name: "Living Room", transportType: kAudioDeviceTransportTypeAirPlay) == "airplayaudio")
        #expect(MediaAudioOutputDevice.iconName(name: "LG UltraFine", transportType: kAudioDeviceTransportTypeDisplayPort) == "tv")
        #expect(MediaAudioOutputDevice.iconName(name: "Jabra", transportType: kAudioDeviceTransportTypeBluetooth) == "headphones")

        let devices = [
            MediaAudioOutputDevice(id: 1, name: "Zed", transportType: 0),
            MediaAudioOutputDevice(id: 2, name: "alpha", transportType: 0),
            MediaAudioOutputDevice(id: 3, name: "Middle", transportType: 0)
        ]
        #expect(MediaAudioOutputDevice.sorted(devices, defaultID: 3).map(\.id) == [3, 2, 1], "default first, then by name")
        #expect(MediaOutputVolumeModel.iconName(level: 0.5, isMuted: true) == "speaker.slash.fill")
        #expect(MediaOutputVolumeModel.iconName(level: 0.2, isMuted: false) == "speaker.wave.1.fill")
        #expect(MediaOutputVolumeModel.iconName(level: 0.9, isMuted: false) == "speaker.wave.3.fill")
    }

    @Test
    func airPlayVolumeStopsAtTheLouderReceiverFirst() {
        #expect(MediaAirPlayManager.volumeSteps(from: 80, to: 20, loudestOther: 50) == [50, 20])
        #expect(MediaAirPlayManager.volumeSteps(from: 40, to: 20, loudestOther: 50) == [20])
        #expect(MediaAirPlayManager.volumeSteps(from: 80, to: 60, loudestOther: 50) == [60])
        #expect(MediaAirPlayManager.escaped("Mehdi's \"Den\"") == "Mehdi's \\\"Den\\\"")
    }

    @Test
    func inlinePeekWidensTheCentreTo380() {
        #expect(MediaClosedLayout.inlinePeekCenterWidth == 380)
        #expect(MediaClosedLayout.inlinePeekColumnWidth(centerWidth: 380, notchWidth: 190) == 83)
        #expect(MediaClosedLayout.inlinePeekColumnWidth(centerWidth: 150, notchWidth: 190) == 0)
        #expect(MusicManager.inlinePeekDuration == .seconds(3))

        let manager = MusicManager(settings: MediaSettings(defaults: Self.makeDefaults()))
        let activity = MusicLiveActivity(manager: manager, settings: manager.settings)
        let context = ClosedActivityContext(closedHeight: 32, notchWidth: 190, isHovering: false, gestureProgress: 0, hasHardwareNotch: true)
        #expect(activity.centerWidthOverride(in: context) == nil, "no peek, no override")
    }

    @Test
    func reverseSwipeFlipsTheSkipDirection() {
        #expect(MusicManager.effectiveSkipDirection(.forward, reversed: false) == .forward)
        #expect(MusicManager.effectiveSkipDirection(.forward, reversed: true) == .backward)
        #expect(MusicManager.effectiveSkipDirection(.backward, reversed: true) == .forward)
    }

    @Test
    func floatingControlsSitBesideTheRightWing() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = MediaControlWindowController.frame(
            for: CGSize(width: 140, height: 32), screenFrame: screen, centerWidth: 190, wingWidth: 20)
        let expectedX: CGFloat = 907 // midX 756 + half centre 95 + wing 20 + spacing 36
        #expect(frame.minX == expectedX)
        #expect(frame.maxY == 982)
        let clamped = MediaControlWindowController.frame(
            for: CGSize(width: 140, height: 32), screenFrame: NSRect(x: 0, y: 0, width: 560, height: 600), centerWidth: 190, wingWidth: 20)
        let expectedMaxX: CGFloat = 552
        #expect(clamped.maxX == expectedMaxX, "kept 8 pt inside the screen")
        #expect(MediaControlOverlayView.buttonSide(notchHeight: 32) == 30.08)
        #expect(MediaControlOverlayView.buttonSide(notchHeight: 24) == 30, "never smaller than 30 pt")
    }

    @Test
    func sideLyricsBudgetMatchesDesign() {
        let width = MediaFeature.sideLyricsRequiredOpenWidth(
            showsPlayer: true, lyricsEnabled: true, showsCalendar: false, showsMirror: false, panelWidth: 280, panelOffset: -20)
        let expected: CGFloat = 744 // 380 player + 280 panel + 20 gap + 20 offset + 44 insets
        #expect(width == expected)
        let withMirror = MediaFeature.sideLyricsRequiredOpenWidth(
            showsPlayer: true, lyricsEnabled: true, showsCalendar: false, showsMirror: true, panelWidth: 280, panelOffset: 0)
        let expectedWithMirror: CGFloat = 964 // … + 220 mirror + 20 gap, no offset
        #expect(withMirror == expectedWithMirror)
        #expect(MediaFeature.sideLyricsRequiredOpenWidth(
            showsPlayer: true, lyricsEnabled: true, showsCalendar: true, showsMirror: false, panelWidth: 280, panelOffset: 0) == 0)
    }

    @Test
    func lyricSweepSlicesWordsByLength() {
        let slices = MediaLyricSweep.wordSlices(in: "I love  you")
        #expect(slices.map(\.word) == ["I", "love", "you"])
        // Weights 2, 5, 4 of 11.
        #expect(abs(slices[0].end - 2.0 / 11.0) < 1e-9)
        #expect(abs(slices[1].start - 2.0 / 11.0) < 1e-9)
        #expect(slices[2].end == 1)
        #expect(MediaLyricSweep.wordProgress(lineProgress: 0.5, start: 0.4, end: 0.6) == 0.5)
        #expect(MediaLyricSweep.wordProgress(lineProgress: 0.1, start: 0.4, end: 0.6) == 0)
        #expect(MediaLyricSweep.wordProgress(lineProgress: 0.9, start: 0.4, end: 0.6) == 1)
        #expect(MediaLyricSweep.feather == 0.06)
    }

    @Test
    func netEaseMatchingTrustsLengthAndArtists() throws {
        let search = Data("""
        {"result":{"songs":[
          {"id":1,"name":"Halo (Karaoke Version)","artists":[{"name":"Beyoncé"}],"duration":261000},
          {"id":2,"name":"Halo","artists":[{"name":"Beyoncé"}],"duration":261500},
          {"id":3,"name":"Halo","artists":[{"name":"Beyoncé"}],"duration":300000}
        ]}}
        """.utf8)
        let songs = MediaNetEaseLyrics.parseSearch(search)
        #expect(songs.count == 3)
        #expect(songs[1].duration == 261.5)
        let best = try #require(MediaNetEaseLyrics.bestMatch(in: songs, title: "Halo", artist: "Beyonce", duration: 261))
        #expect(best.id == 2, "the karaoke cut and the 300 s recording are rejected")

        let url = try #require(MediaNetEaseLyrics.searchURL(title: "AC/DC & Me", artist: "A/B"))
        #expect(url.absoluteString.contains("AC%2FDC%20%26%20Me%20A%20B"))
        #expect(MediaNetEaseLyrics.lyricURL(songID: 42)?.absoluteString == "https://music.163.com/api/song/lyric?id=42&lv=-1")

        let lyric = MediaNetEaseLyrics.parseLyrics(Data(#"{"lrc":{"lyric":"[00:01.00]Hello\n[00:03.50]World"}}"#.utf8))
        #expect(lyric.availability == .timed)
        #expect(lyric.lines.map(\.text) == ["Hello", "World"])
        #expect(MediaNetEaseLyrics.parseLyrics(Data(#"{"nolyric":true}"#.utf8)).availability == .instrumental)
        #expect(MediaNetEaseLyrics.parseLyrics(Data(#"{"uncollected":true}"#.utf8)).availability == .unavailable)
    }

    @Test
    func openHUDStateShowsOnVolumeAndClampsLevel() {
        let state = MediaOpenHUDState()
        #expect(!state.isActive)
        state.show(level: 1.4)
        #expect(state.isActive)
        #expect(state.level == 1)
        state.show(level: 0)
        #expect(state.isMuted)
        state.stop()
        #expect(!state.isActive)
    }

    // MARK: Helpers

    private static func makeDefaults() -> UserDefaults {
        let suite = "MediaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()
    }
}
