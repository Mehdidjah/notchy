import AppKit
import Combine
import SwiftUI

/// The island's music state: reads Apple Music and Spotify through AppleScript, keeps the
/// current track, artwork, colours, position and lyrics, and sends transport commands.
///
/// Players are woken by their distributed notifications and re-read 25 ms after each
/// command; between readings the position is extrapolated from the last anchor, so the
/// slider moves at 30 fps without polling.
@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager(settings: .shared)

    enum SkipDirection: Sendable {
        case backward
        case forward
    }

    /// Lets the skip buttons animate when a horizontal swipe skipped.
    struct SkipPulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MediaSkipBehavior
    }

    static let defaultArtwork: NSImage = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Album Art")
        ?? NSImage(size: NSSize(width: 1, height: 1))

    static let seekInterval: TimeInterval = 10
    private static let optimisticRecoveryTimeout: Duration = .seconds(2)
    private static let flipDuration: TimeInterval = 0.45
    private static let manualArtworkHandoff: TimeInterval = 0.225
    /// The expanding view hides itself after 3 s.
    static let inlinePeekDuration: Duration = .seconds(3)

    // MARK: - Published state

    @Published private(set) var songTitle = MediaPlaceholder.title
    @Published private(set) var artistName = MediaPlaceholder.artist
    @Published private(set) var album = MediaPlaceholder.album
    @Published private(set) var albumArt: NSImage = MusicManager.defaultArtwork
    @Published private(set) var albumArtGlowTexture: NSImage = MusicManager.defaultArtwork
    @Published private(set) var isArtworkWide = false
    @Published private(set) var usingAppIconForArtwork = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isPlayerIdle = true
    @Published private(set) var isCurrentTrackExplicit = false
    @Published private(set) var avgColor: MediaRGB = .white
    @Published private(set) var secondaryColor: MediaRGB = .gray
    @Published private(set) var activeSource: MediaSourceKind?
    @Published private(set) var songDuration: TimeInterval = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var timestampDate = Date()
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: MediaRepeatMode = .off
    @Published private(set) var isLiveStream = false
    @Published private(set) var isAdvertisement = false
    @Published private(set) var flipAngle: Double = 0
    @Published private(set) var skipPulse: SkipPulse?
    /// nil while unknown or when the source cannot favourite.
    @Published private(set) var isCurrentTrackFavorited: Bool?
    @Published private(set) var lyricLines: [MediaLyricLine] = []
    @Published private(set) var currentLyricIndex = -1
    @Published private(set) var currentLyrics = ""
    @Published private(set) var lyricsAvailability: MediaLyricsAvailability = .unavailable
    /// The inline sneak peek is showing: the closed notch is 380 pt wide with the title on
    /// the left and the artist on the right.
    @Published private(set) var isInlinePeekActive = false

    let settings: MediaSettings

    // MARK: - Private state

    private struct ContentIdentity: Equatable {
        let source: MediaSourceKind
        let title: String
        let artist: String
        let album: String
        let trackIdentifier: String?

        init(_ snapshot: MediaPlaybackSnapshot) {
            source = snapshot.source
            title = snapshot.title
            artist = snapshot.artist
            album = snapshot.album
            trackIdentifier = snapshot.trackIdentifier
        }
    }

    private struct CachedArtwork {
        let key: String
        let data: Data?
    }

    private var isStarted = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var cancellables = Set<AnyCancellable>()
    private var snapshots: [MediaSourceKind: MediaPlaybackSnapshot] = [:]
    private var lastPlayingAt: [MediaSourceKind: Date] = [:]
    private var refreshGeneration: [MediaSourceKind: Int] = [:]
    private var artworkCache: [MediaSourceKind: CachedArtwork] = [:]
    private var artworkLoadTasks: [MediaSourceKind: Task<Void, Never>] = [:]
    private var stoppedRefreshTasks: [MediaSourceKind: Task<Void, Never>] = [:]
    private var optimistic = MediaOptimisticPlayback()
    private var optimisticRecoveryTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var flipCooldown = false
    private var lastFlipDirection: SkipDirection = .forward
    private var handoffDeadline: Date?
    private var handoffTask: Task<Void, Never>?
    private var artworkGeneration = 0
    private var appliedArtworkData: Data?
    /// The artwork key whose cover (or app-icon fallback) is on screen.
    private var appliedArtworkKey: String?
    /// Keys whose embedded Music artwork is being read right now; the app-icon fallback
    /// waits for them instead of flashing.
    private var artworkFetchInFlight = Set<String>()
    private var lastContent: ContentIdentity?
    private var liveDetector = MediaLiveStreamDetector()
    private var explicitTask: Task<Void, Never>?
    private var favoriteTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lyricsKey: String?
    private var lyricSyncTask: Task<Void, Never>?
    private var skipToken = 0
    private var inlinePeekTask: Task<Void, Never>?

    init(settings: MediaSettings) {
        self.settings = settings
    }

    // MARK: - Derived state

    var bundleIdentifier: String? { activeSource?.bundleIdentifier }

    /// Playing, or paused on a real track.
    var hasActiveSession: Bool {
        MediaPlaceholder.hasActiveSession(isPlaying: isPlaying, title: songTitle, artist: artistName)
    }

    /// Playing, or paused and not yet idle on a real track: what the closed activity needs.
    var hasActiveMusicSnapshot: Bool {
        isPlaying || (!isPlayerIdle && MediaPlaceholder.hasRealMetadata(title: songTitle, artist: artistName))
    }

    var brandAccentColor: Color { activeSource?.brandAccent ?? .accentColor }

    /// Music is the source, which is what AirPlay routing needs.
    var isAppleMusicActive: Bool { activeSource == .appleMusic }

    /// Only Music exposes favouriting to AppleScript.
    var canFavorite: Bool { activeSource == .appleMusic }

    var isInInstrumentalBreak: Bool {
        MediaLyricsEngine.isInstrumentalBreak(lines: lyricLines, index: currentLyricIndex, duration: songDuration)
    }

    var hasTimedLyrics: Bool { lyricLines.contains(where: \.isTimed) }

    func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        MediaPlaybackMath.estimatedPosition(
            elapsed: elapsedTime,
            anchor: timestampDate,
            rate: playbackRate,
            isPlaying: isPlaying,
            duration: songDuration,
            at: date
        )
    }

    func currentLyricSweepProgress(at date: Date = Date()) -> Double {
        MediaLyricsEngine.sweepProgress(
            in: lyricLines,
            index: currentLyricIndex,
            position: lyricPosition(at: date),
            duration: songDuration
        )
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let distributed = DistributedNotificationCenter.default()
        for source in MediaSourceKind.allCases {
            let name = Notification.Name(Self.notificationName(for: source))
            let token = distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let state = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated {
                    self?.handlePlayerNotification(source: source, playerState: state)
                }
            }
            observers.append((distributed, token))
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let source = MediaSourceKind(bundleIdentifier: app?.bundleIdentifier)
                let launched = note.name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    guard let self, let source else { return }
                    if launched {
                        self.scheduleRefresh(source, after: .seconds(1))
                    } else {
                        self.sourceDidQuit(source)
                    }
                }
            }
            observers.append((workspace, token))
        }

        settings.$sourcePreference
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resolveActiveSource()
                self?.forceRefresh()
            }
            .store(in: &cancellables)

        settings.$enableLyrics
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.lyricsKey = nil
                    self.prepareLyrics()
                } else {
                    self.discardLyrics()
                }
            }
            .store(in: &cancellables)

        settings.$colorExtractionMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let data = self.appliedArtworkData else { return }
                self.processArtwork(data)
            }
            .store(in: &cancellables)

        forceRefresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        cancellables.removeAll()
        for task in artworkLoadTasks.values { task.cancel() }
        for task in stoppedRefreshTasks.values { task.cancel() }
        artworkLoadTasks.removeAll()
        stoppedRefreshTasks.removeAll()
        [optimisticRecoveryTask, idleTask, handoffTask, explicitTask, favoriteTask, lyricsTask, inlinePeekTask]
            .forEach { $0?.cancel() }
        if isInlinePeekActive { isInlinePeekActive = false }
        stopLyricSync()
    }

    /// Re-reads every allowed player that is running (called when the island opens).
    func forceRefresh() {
        guard isStarted else { return }
        for source in settings.sourcePreference.allowedSources {
            if MediaScripting.isRunning(source) {
                refresh(source)
            } else if snapshots[source] != nil {
                sourceDidQuit(source)
            }
        }
        if settings.sourcePreference.allowedSources.allSatisfy({ snapshots[$0] == nil }) {
            resolveActiveSource()
        }
    }

    // MARK: - Commands

    func togglePlay() {
        guard let source = activeSource else {
            // Nothing is open: start the preferred player.
            let source: MediaSourceKind = settings.sourcePreference == .spotify ? .spotify : .appleMusic
            Task { await MediaScripting.perform(.play, on: source, launchIfNeeded: true) }
            return
        }
        let target = !isPlaying
        optimistic.begin(expecting: target)
        // Re-anchor so the slider neither jumps back on pause nor skips ahead on resume.
        elapsedTime = estimatedPlaybackPosition()
        timestampDate = Date()
        setPlaying(target, animation: .smooth(duration: 0.18))

        optimisticRecoveryTask?.cancel()
        optimisticRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.optimisticRecoveryTimeout)
            guard !Task.isCancelled, let self, self.optimistic.cancel(ifExpecting: target) else { return }
            self.refresh(source)
        }
        send(target ? .play : .pause, to: source)
    }

    func play() {
        guard !isPlaying else { return }
        togglePlay()
    }

    func pause() {
        guard isPlaying else { return }
        togglePlay()
    }

    func nextTrack() {
        guard let source = activeSource else { return }
        lastFlipDirection = .forward
        beginManualArtworkHandoff()
        send(.nextTrack, to: source)
    }

    func previousTrack() {
        guard let source = activeSource else { return }
        lastFlipDirection = .backward
        beginManualArtworkHandoff()
        send(.previousTrack, to: source)
    }

    func seek(to position: TimeInterval) {
        guard let source = activeSource, !isLiveStream else { return }
        let target = MediaPlaybackMath.isUsableDuration(songDuration) ? min(max(0, position), songDuration) : max(0, position)
        elapsedTime = target
        timestampDate = Date()
        send(.seek(target), to: source)
    }

    /// Seeks by `offset`; past either end of the track it skips to the neighbouring one.
    func seek(by offset: TimeInterval) {
        guard !isLiveStream, songDuration > 0 else { return }
        let current = estimatedPlaybackPosition()
        if offset < 0, current <= abs(offset) {
            previousTrack()
            return
        }
        if offset > 0, songDuration - current <= abs(offset) {
            nextTrack()
            return
        }
        seek(to: min(max(0, current + offset), songDuration))
    }

    func toggleShuffle() {
        guard let source = activeSource else { return }
        send(.toggleShuffle, to: source)
    }

    func toggleRepeat() {
        guard let source = activeSource else { return }
        send(.cycleRepeat, to: source)
    }

    func toggleFavorite() {
        guard activeSource == .appleMusic, let current = isCurrentTrackFavorited else { return }
        let target = !current
        isCurrentTrackFavorited = target
        favoriteTask?.cancel()
        let identity = lastContent
        favoriteTask = Task { [weak self] in
            let succeeded = await MediaScripting.setAppleMusicFavorite(target)
            guard !Task.isCancelled, let self, self.lastContent == identity else { return }
            if !succeeded { self.isCurrentTrackFavorited = current }
        }
    }

    /// A two-finger horizontal swipe: skips a track or seeks ±10 s, and pulses the matching
    /// button. The host forwards swipes over the closed activity or the Home tab, passing
    /// `.forward` for a swipe to the left; "Reverse swipe gestures" flips it here.
    func handleSkipGesture(direction swipeDirection: SkipDirection) {
        guard settings.horizontalGestures else { return }
        guard !isPlayerIdle || activeSource != nil else { return }
        let direction = Self.effectiveSkipDirection(swipeDirection, reversed: settings.reverseSwipeGestures)
        let behavior = settings.gestureBehavior
        switch behavior {
        case .track:
            direction == .forward ? nextTrack() : previousTrack()
        case .tenSecond:
            seek(by: direction == .forward ? Self.seekInterval : -Self.seekInterval)
        }
        skipToken &+= 1
        skipPulse = SkipPulse(token: skipToken, direction: direction, behavior: behavior)
    }

    static func effectiveSkipDirection(_ direction: SkipDirection, reversed: Bool) -> SkipDirection {
        guard reversed else { return direction }
        return direction == .forward ? .backward : .forward
    }

    func openMusicApp() {
        let bundleID = activeSource?.bundleIdentifier ?? MediaSourceKind.appleMusic.bundleIdentifier
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: MediaCommand, to source: MediaSourceKind) {
        let slowCommand = source == .appleMusic && (command == .toggleShuffle || command == .cycleRepeat)
        let delay: Duration = slowCommand ? .milliseconds(150) : .milliseconds(25)
        Task { [weak self] in
            await MediaScripting.perform(command, on: source)
            try? await Task.sleep(for: delay)
            self?.refresh(source)
        }
    }

    // MARK: - Reading the players

    private static func notificationName(for source: MediaSourceKind) -> String {
        switch source {
        case .appleMusic: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    private func handlePlayerNotification(source: MediaSourceKind, playerState: String?) {
        guard isStarted else { return }
        if playerState == "Playing" {
            lastPlayingAt[source] = Date()
        }
        if playerState == "Stopped" {
            // Music announces "Stopped" while quitting; scripting it then would relaunch it.
            // Mark it paused now and look again once it has had time to go away.
            if var snapshot = snapshots[source], snapshot.isPlaying {
                snapshot.isPlaying = false
                snapshot.position = MediaPlaybackMath.estimatedPosition(
                    elapsed: snapshot.position, anchor: snapshot.lastUpdated, rate: snapshot.playbackRate,
                    isPlaying: true, duration: snapshot.duration, at: Date())
                snapshot.lastUpdated = Date()
                ingest(snapshot)
            }
            scheduleRefresh(source, after: .seconds(1))
            return
        }
        refresh(source)
    }

    private func scheduleRefresh(_ source: MediaSourceKind, after delay: Duration) {
        stoppedRefreshTasks[source]?.cancel()
        stoppedRefreshTasks[source] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.stoppedRefreshTasks[source] = nil
            self.refresh(source)
        }
    }

    private func refresh(_ source: MediaSourceKind) {
        guard isStarted else { return }
        guard MediaScripting.isRunning(source) else {
            sourceDidQuit(source)
            return
        }
        let generation = (refreshGeneration[source] ?? 0) &+ 1
        refreshGeneration[source] = generation
        Task { [weak self] in
            guard var snapshot = await MediaScripting.fetchSnapshot(for: source) else { return }
            guard let self, self.isStarted, self.refreshGeneration[source] == generation else { return }
            let fetchedArtwork = await self.attachArtwork(to: &snapshot)
            guard self.isStarted else { return }
            if self.refreshGeneration[source] == generation {
                self.ingest(snapshot)
            } else if fetchedArtwork, var latest = self.snapshots[source],
                      latest.artworkKey == snapshot.artworkKey, latest.artworkData == nil {
                // A newer reading overtook this one while the cover was read: hand the
                // cover (or its absence) to that reading instead of dropping it.
                latest.artworkData = snapshot.artworkData
                self.ingest(latest)
            }
        }
    }

    /// Fills in cached artwork, reads Music's embedded cover for a new track, and starts the
    /// slower lookups (catalogue, Spotify download) that patch the snapshot when they land.
    /// Returns whether Music's cover was read during this call.
    private func attachArtwork(to snapshot: inout MediaPlaybackSnapshot) async -> Bool {
        let source = snapshot.source
        let key = snapshot.artworkKey
        if let cached = artworkCache[source], cached.key == key {
            snapshot.artworkData = cached.data
            return false
        }
        guard MediaPlaceholder.hasRealMetadata(title: snapshot.title, artist: snapshot.artist) else { return false }

        artworkLoadTasks[source]?.cancel()
        artworkCache[source] = CachedArtwork(key: key, data: nil)
        switch source {
        case .appleMusic:
            artworkFetchInFlight.insert(key)
            let data = await MediaScripting.fetchAppleMusicArtwork()
            artworkFetchInFlight.remove(key)
            guard artworkCache[source]?.key == key else { return false }
            artworkCache[source] = CachedArtwork(key: key, data: data)
            snapshot.artworkData = data
            if data == nil { loadDeferredArtwork(for: snapshot) }
            return true
        case .spotify:
            loadDeferredArtwork(for: snapshot)
            return false
        }
    }

    private func loadDeferredArtwork(for snapshot: MediaPlaybackSnapshot) {
        let source = snapshot.source
        let key = snapshot.artworkKey
        let title = snapshot.title
        let artist = snapshot.artist
        let album = snapshot.album
        let url = snapshot.artworkURL
        artworkLoadTasks[source]?.cancel()
        artworkLoadTasks[source] = Task { [weak self] in
            let data: Data?
            switch source {
            case .appleMusic:
                data = await MediaArtworkResolver.shared.catalogArtwork(title: title, artist: artist, album: album)
            case .spotify:
                if let url {
                    data = await MediaArtworkResolver.shared.artwork(from: url)
                } else {
                    data = nil
                }
            }
            guard !Task.isCancelled, let self, let data, self.artworkCache[source]?.key == key else { return }
            self.artworkCache[source] = CachedArtwork(key: key, data: data)
            guard var latest = self.snapshots[source], latest.artworkKey == key else { return }
            latest.artworkData = data
            self.ingest(latest)
        }
    }

    private func sourceDidQuit(_ source: MediaSourceKind) {
        stoppedRefreshTasks[source]?.cancel()
        stoppedRefreshTasks[source] = nil
        artworkLoadTasks[source]?.cancel()
        artworkLoadTasks[source] = nil
        artworkCache[source] = nil
        guard snapshots.removeValue(forKey: source) != nil || activeSource == source else { return }
        if activeSource == source {
            activeSource = nil
        }
        resolveActiveSource()
    }

    private func ingest(_ snapshot: MediaPlaybackSnapshot) {
        let previous = snapshots[snapshot.source]
        snapshots[snapshot.source] = snapshot
        if snapshot.isPlaying, previous?.isPlaying != true || previous?.artworkKey != snapshot.artworkKey {
            lastPlayingAt[snapshot.source] = Date()
        }
        resolveActiveSource()
    }

    /// Picks the player the notch follows: the playing one (the most recently started if
    /// both play), else the one already shown, else the last one used.
    private func resolveActiveSource() {
        let allowed = settings.sourcePreference.allowedSources
        let candidates = allowed.compactMap { snapshots[$0] }
        let recency: (MediaPlaybackSnapshot) -> Date = { [lastPlayingAt] in lastPlayingAt[$0.source] ?? .distantPast }

        let chosen: MediaPlaybackSnapshot?
        if let playing = candidates.filter(\.isPlaying).max(by: { recency($0) < recency($1) }) {
            chosen = playing
        } else if let current = activeSource, allowed.contains(current), let snapshot = snapshots[current] {
            chosen = snapshot
        } else {
            chosen = candidates
                .filter { MediaPlaceholder.hasRealMetadata(title: $0.title, artist: $0.artist) }
                .max { recency($0) < recency($1) } ?? candidates.first
        }

        guard let chosen else {
            resetToPlaceholder()
            return
        }
        if activeSource != chosen.source {
            activeSource = chosen.source
            isCurrentTrackFavorited = nil
        }
        apply(chosen)
    }

    // MARK: - Applying a reading

    private func apply(_ snapshot: MediaPlaybackSnapshot) {
        var wantsSneakPeek = false
        let advertisementStarted = snapshot.isAdvertisement && !isAdvertisement
        if isAdvertisement != snapshot.isAdvertisement { isAdvertisement = snapshot.isAdvertisement }
        if advertisementStarted { endInlinePeek() }

        // Play state, honouring an optimistic toggle until the player confirms it.
        let expected = optimistic.expectedState
        if optimistic.shouldApply(eventIsPlaying: snapshot.isPlaying) {
            if expected != nil {
                optimisticRecoveryTask?.cancel()
                optimisticRecoveryTask = nil
            }
            if snapshot.isPlaying != isPlaying {
                setPlaying(snapshot.isPlaying, animation: expected == snapshot.isPlaying ? .smooth(duration: 0.18) : .smooth)
                if snapshot.isPlaying, !snapshot.title.isEmpty, !snapshot.artist.isEmpty {
                    wantsSneakPeek = true
                }
            } else {
                updateIdleState(playing: snapshot.isPlaying)
            }
        }

        // Track content.
        let identity = ContentIdentity(snapshot)
        let trackChanged = identity != lastContent
        let artworkChanged = snapshot.artworkData != nil && snapshot.artworkData != appliedArtworkData

        if songTitle != snapshot.title { songTitle = snapshot.title }
        if artistName != snapshot.artist { artistName = snapshot.artist }
        if album != snapshot.album { album = snapshot.album }
        let durationChanged = songDuration != snapshot.duration
        if durationChanged { songDuration = snapshot.duration }

        if trackChanged || artworkChanged {
            triggerFlip()
        }
        let artworkKey = snapshot.artworkKey
        if artworkChanged, let data = snapshot.artworkData {
            appliedArtworkData = data
            appliedArtworkKey = artworkKey
            processArtwork(data)
        } else if snapshot.artworkData == nil, appliedArtworkKey != artworkKey,
                  !artworkFetchInFlight.contains(artworkKey) {
            // No cover for this track (yet): show the player's icon.
            appliedArtworkData = nil
            appliedArtworkKey = artworkKey
            useAppIconArtwork(for: snapshot.source)
        }

        if trackChanged {
            lastContent = identity
            liveDetector.reset()
            refreshExplicitFlag(snapshot)
            refreshFavorite()
            prepareLyrics()
            if settings.sneakPeekOnTrackChange, snapshot.isPlaying, !snapshot.title.isEmpty, !snapshot.artist.isEmpty {
                wantsSneakPeek = true
            }
        } else if durationChanged {
            prepareLyrics()
        }

        // Position, rate and modes.
        if elapsedTime != snapshot.position { elapsedTime = snapshot.position }
        if playbackRate != snapshot.playbackRate { playbackRate = snapshot.playbackRate }
        if isShuffled != snapshot.isShuffled { isShuffled = snapshot.isShuffled }
        if repeatMode != snapshot.repeatMode { repeatMode = snapshot.repeatMode }
        liveDetector.observe(isPlaying: snapshot.isPlaying, position: snapshot.position, duration: snapshot.duration)
        if isLiveStream != liveDetector.isLive { isLiveStream = liveDetector.isLive }
        if timestampDate != snapshot.lastUpdated { timestampDate = snapshot.lastUpdated }

        updateLyricSyncState()
        if wantsSneakPeek, !isAdvertisement, !advertisementStarted { requestTrackSneakPeek() }
    }

    private func setPlaying(_ playing: Bool, animation: Animation?) {
        var transaction = Transaction()
        transaction.animation = animation
        withTransaction(transaction) {
            isPlaying = playing
        }
        updateIdleState(playing: playing)
        updateLyricSyncState()
    }

    /// Playing clears idle at once; a pause becomes idle after the inactivity timeout.
    private func updateIdleState(playing: Bool) {
        if playing {
            idleTask?.cancel()
            idleTask = nil
            if isPlayerIdle { isPlayerIdle = false }
            return
        }
        guard idleTask == nil, !isPlayerIdle else { return }
        let wait = settings.waitInterval
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.idleTask = nil
            withAnimation {
                self.isPlayerIdle = !self.isPlaying
            }
        }
    }

    private func resetToPlaceholder() {
        let hasState = activeSource != nil || isPlaying
            || MediaPlaceholder.hasRealMetadata(title: songTitle, artist: artistName)
        guard hasState else { return }
        activeSource = nil
        optimistic = MediaOptimisticPlayback()
        optimisticRecoveryTask?.cancel()
        if isPlaying {
            setPlaying(false, animation: .smooth)
        }
        songTitle = MediaPlaceholder.title
        artistName = MediaPlaceholder.artist
        album = MediaPlaceholder.album
        songDuration = 0
        elapsedTime = 0
        timestampDate = Date()
        isShuffled = false
        repeatMode = .off
        liveDetector.reset()
        isLiveStream = false
        lastContent = nil
        appliedArtworkData = nil
        appliedArtworkKey = nil
        artworkGeneration &+= 1
        withAnimation(.smooth) {
            albumArt = Self.defaultArtwork
        }
        albumArtGlowTexture = Self.defaultArtwork
        isArtworkWide = false
        usingAppIconForArtwork = false
        avgColor = .white
        secondaryColor = .gray
        isCurrentTrackExplicit = false
        isCurrentTrackFavorited = nil
        isAdvertisement = false
        explicitTask?.cancel()
        discardLyrics()
    }

    /// The grey line under the notch (standard), or the closed
    /// notch widened for 3 s with the title and artist either side of the camera (inline).
    private func requestTrackSneakPeek() {
        guard settings.enableSneakPeek, settings.showStandardMediaControls, isPlaying, !isAdvertisement else { return }
        switch settings.sneakPeekStyle {
        case .standard:
            IslandActivityCenter.shared.requestSneakPeek(SneakPeek(
                kind: .music,
                systemImage: "music.note",
                title: Self.sneakPeekText(title: songTitle, artist: artistName),
                tint: .gray,
                duration: .milliseconds(1_500)
            ))
        case .inline:
            beginInlinePeek()
        }
    }

    private func beginInlinePeek() {
        inlinePeekTask?.cancel()
        if !isInlinePeekActive {
            withAnimation(.smooth) { isInlinePeekActive = true }
        }
        inlinePeekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.inlinePeekDuration)
            guard !Task.isCancelled, let self else { return }
            self.inlinePeekTask = nil
            withAnimation(.smooth) { self.isInlinePeekActive = false }
        }
    }

    private func endInlinePeek() {
        inlinePeekTask?.cancel()
        inlinePeekTask = nil
        guard isInlinePeekActive else { return }
        withAnimation(.smooth) { isInlinePeekActive = false }
    }

    /// Standard peek line: "Title - Artist".
    static func sneakPeekText(title: String, artist: String) -> String {
        "\(title) - \(artist)"
    }

    // MARK: - Artwork

    /// Half-turns the artwork on a content change; bursts within 0.6 s give one flip.
    private func triggerFlip() {
        guard !flipCooldown else { return }
        flipCooldown = true
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.easeInOut(duration: Self.flipDuration)) {
            flipAngle += delta
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.flipDuration + 0.15))
            self?.flipCooldown = false
        }
    }

    /// After a manual skip, new artwork waits until the flip is half way.
    private func beginManualArtworkHandoff() {
        handoffDeadline = Date().addingTimeInterval(Self.manualArtworkHandoff)
    }

    private func processArtwork(_ data: Data) {
        artworkGeneration &+= 1
        let generation = artworkGeneration
        let mode = settings.colorExtractionMode
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let analysis = MediaArtworkProcessing.analyze(data: data, mode: mode) else { return }
            await self?.receiveArtwork(analysis, generation: generation, isAppIcon: false)
        }
    }

    private func useAppIconArtwork(for source: MediaSourceKind) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        var rect = NSRect(x: 0, y: 0, width: 512, height: 512)
        guard let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        artworkGeneration &+= 1
        let generation = artworkGeneration
        let mode = settings.colorExtractionMode
        let box = MediaCGImageBox(image: cgImage)
        Task.detached(priority: .userInitiated) { [weak self] in
            let analysis = MediaArtworkProcessing.analyze(cgImage: box.image, mode: mode)
            await self?.receiveArtwork(analysis, generation: generation, isAppIcon: true)
        }
    }

    private func receiveArtwork(_ analysis: MediaArtworkAnalysis, generation: Int, isAppIcon: Bool) {
        guard generation == artworkGeneration else { return }
        if let deadline = handoffDeadline, deadline > Date() {
            handoffTask?.cancel()
            handoffTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
                guard !Task.isCancelled, let self, generation == self.artworkGeneration else { return }
                self.handoffDeadline = nil
                self.applyArtwork(analysis, isAppIcon: isAppIcon)
            }
            return
        }
        handoffDeadline = nil
        applyArtwork(analysis, isAppIcon: isAppIcon)
    }

    private func applyArtwork(_ analysis: MediaArtworkAnalysis, isAppIcon: Bool) {
        withAnimation(.smooth) {
            albumArt = analysis.image
        }
        albumArtGlowTexture = analysis.glow
        isArtworkWide = analysis.isWide
        usingAppIconForArtwork = isAppIcon
        avgColor = analysis.primary
        secondaryColor = analysis.secondary
    }

    private func refreshExplicitFlag(_ snapshot: MediaPlaybackSnapshot) {
        explicitTask?.cancel()
        if isCurrentTrackExplicit { isCurrentTrackExplicit = false }
        guard MediaPlaceholder.hasRealMetadata(title: snapshot.title, artist: snapshot.artist) else { return }
        let identity = ContentIdentity(snapshot)
        explicitTask = Task { [weak self] in
            let explicit = await MediaArtworkResolver.shared.isExplicit(
                title: snapshot.title, artist: snapshot.artist, album: snapshot.album)
            guard !Task.isCancelled, let self, self.lastContent == identity else { return }
            if self.isCurrentTrackExplicit != explicit { self.isCurrentTrackExplicit = explicit }
        }
    }

    private func refreshFavorite() {
        favoriteTask?.cancel()
        isCurrentTrackFavorited = nil
        guard activeSource == .appleMusic, settings.displayedSlots(canFavorite: true).contains(.likeTrack) else { return }
        let identity = lastContent
        favoriteTask = Task { [weak self] in
            let value = await MediaScripting.fetchAppleMusicFavorite()
            guard !Task.isCancelled, let self, self.lastContent == identity else { return }
            self.isCurrentTrackFavorited = value
        }
    }

    // MARK: - Lyrics

    private func prepareLyrics() {
        guard settings.enableLyrics else {
            discardLyrics()
            return
        }
        guard !isAdvertisement, !MediaLyricsEngine.namesNoParticularTrack(title: songTitle, artist: artistName) else {
            discardLyrics()
            return
        }
        let key = [songTitle, artistName, album, String(Int(songDuration.rounded()))]
            .joined(separator: "|")
            .lowercased()
        guard key != lyricsKey else { return }
        lyricsKey = key
        lyricsTask?.cancel()
        stopLyricSync()
        lyricLines = []
        currentLyricIndex = -1
        lyricsAvailability = .loading
        currentLyrics = "Loading lyrics..."

        let title = songTitle
        let artist = artistName
        let album = album
        let duration = songDuration
        lyricsTask = Task { [weak self] in
            let resolution = await MediaLyricsProvider.shared.lyrics(
                title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.lyricsKey == key else { return }
            self.applyLyrics(resolution)
        }
    }

    private func applyLyrics(_ resolution: MediaLyricsResolution) {
        lyricLines = resolution.lines
        lyricsAvailability = resolution.availability
        currentLyricIndex = -1
        guard !resolution.lines.isEmpty else {
            currentLyrics = resolution.availability == .instrumental ? "Instrumental" : "No lyrics found"
            stopLyricSync()
            return
        }
        updateCurrentLyric(at: lyricPosition())
        updateLyricSyncState()
    }

    private func discardLyrics() {
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsKey = nil
        stopLyricSync()
        if !lyricLines.isEmpty { lyricLines = [] }
        if currentLyricIndex != -1 { currentLyricIndex = -1 }
        if !currentLyrics.isEmpty { currentLyrics = "" }
        if lyricsAvailability != .unavailable { lyricsAvailability = .unavailable }
    }

    private func updateCurrentLyric(at position: TimeInterval) {
        guard !lyricLines.isEmpty else { return }
        guard hasTimedLyrics else {
            if currentLyricIndex != -1 { currentLyricIndex = -1 }
            if !currentLyrics.isEmpty { currentLyrics = "" }
            return
        }
        let index = MediaLyricsEngine.currentIndex(in: lyricLines, at: position)
        let text = lyricLines.indices.contains(index) ? lyricLines[index].text : ""
        if index != currentLyricIndex { currentLyricIndex = index }
        if currentLyrics != text { currentLyrics = text }
    }

    /// Playback position for lyrics, a quarter second ahead of the voice.
    private func lyricPosition(at date: Date = Date()) -> TimeInterval {
        let position: TimeInterval
        if songDuration > 0 {
            position = estimatedPlaybackPosition(at: date)
        } else if isPlaying {
            position = max(0, elapsedTime + date.timeIntervalSince(timestampDate) * playbackRate)
        } else {
            position = max(0, elapsedTime)
        }
        return position + MediaLyricsEngine.leadTime
    }

    private func updateLyricSyncState() {
        if settings.enableLyrics, isPlaying, hasTimedLyrics {
            startLyricSync()
        } else {
            stopLyricSync()
            if hasTimedLyrics { updateCurrentLyric(at: lyricPosition()) }
        }
    }

    /// Sleeps until the next line is due (50...250 ms) and moves the current line.
    private func startLyricSync() {
        guard lyricSyncTask == nil else { return }
        lyricSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let position = self.lyricPosition()
                self.updateCurrentLyric(at: position)
                let delay = MediaLyricsEngine.delayUntilNextLine(in: self.lyricLines, after: position)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    #if DEBUG
    /// Feeds a reading in as if a player had reported it, for previews and tests.
    func injectSnapshotForPreview(_ snapshot: MediaPlaybackSnapshot) {
        ingest(snapshot)
    }
    #endif
}

/// Carries a `CGImage` into a detached task.
struct MediaCGImageBox: @unchecked Sendable {
    let image: CGImage
}
