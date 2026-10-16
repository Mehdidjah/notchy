# Atoll spec: MUSIC / MEDIA (MusicManager, media controllers, MediaRemote adapter, closed-notch music live activity, sneak peek, visualizer + CoreAudio process tap, open-notch standard and minimalistic players, horizontal skip gestures, floating control overlay, lyrics, animated artwork, color extraction, marquee)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

All file:line references below are relative to the Atoll source clone at /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/atoll-clone/Atoll/DynamicIsland (abbreviated DI/). REA evidence is from /private/tmp/claude-501/-Users-a-dynamic-iland-dynamic-island/b501c539-18bc-4747-a9c4-d824916ad38f/scratchpad/rea-out and from the installed /Applications/Atoll.app (2.3.3, build 20260720004).

ARCHITECTURE. One singleton `MusicManager` (DI/managers/MusicManager.swift:534) owns the UI-facing @Published state (title/artist/album/artwork/isPlaying/elapsed/duration/playbackRate/shuffle/repeat/colors/lyrics/...) and delegates to exactly one active `MediaControllerProtocol` (DI/MediaControllers/MediaControllerProtocol.swift:27) chosen by `Defaults[.mediaController]` (default `.appleMusic` on macOS >= 15.4, else `.nowPlaying`; Constants.swift:1529). Each controller publishes a `PlaybackState` struct (DI/models/PlaybackState.swift:31) through Combine; MusicManager diffs it (`updateFromPlaybackState`, MusicManager.swift:915) and only assigns changed fields. Seven sources: Now Playing (PRIVATE MediaRemote via the bundled `mediaremote-adapter.pl` + `MediaRemoteAdapter.framework` perl bridge, streamed as JSON lines from a child `/usr/bin/perl` Process), Apple Music (AppleScript + DistributedNotification `com.apple.Music.playerInfo` + iTunes Search API artwork fallback), Spotify (AppleScript + DistributedNotification `com.spotify.client.PlaybackStateChanged` + artwork URL download + canvas/explicit web scraping), YouTube Music (th-ch desktop app HTTP API http://localhost:26538 /api/v1 + WebSocket, 2 s poll fallback), TIDAL / Cider / Amazon Music (the same MediaRemote stream filtered to one bundle id; TIDAL shuffle/repeat/favorite read via the Accessibility API, Cider favorite via http://localhost:10767/api/v1/playback). Commands for the MediaRemote-based sources are sent through `MRMediaRemoteSendCommand(0 play /1 pause /2 toggle /4 next /5 prev)`, `MRMediaRemoteSetElapsedTime`, `MRMediaRemoteSetShuffleMode(1 off / 3 on)`, `MRMediaRemoteSetRepeatMode(1 off /2 one /3 all)` resolved at runtime with `CFBundleGetFunctionPointerForName` from `/System/Library/PrivateFrameworks/MediaRemote.framework` (NowPlayingController.swift:66-93). REA CONFIRMS: the installed binary contains the strings `/System/Library/PrivateFrameworks/MediaRemote.framework`, `MRMediaRemoteSendCommand/SetElapsedTime/SetShuffleMode/SetRepeatMode`, `mediaremote-adapter`, `MediaRemoteAdapter.framework`; graph.json lists `Contents/Resources/MediaRemoteAdapter.framework/...` and the Resources dir holds `mediaremote-adapter.pl` and `default.metallib`; macho.json shows MediaRemote is NOT a link-time dependency (loaded dynamically), while MusicKit, CoreAudio, AVFAudio, Metal/MetalKit, Lottie.framework and Sparkle.framework ARE linked; `nm -u` shows `_AudioHardwareCreateProcessTap`, `_AudioHardwareDestroyProcessTap`, `_AudioHardwareCreateAggregateDevice`, `CATapDescription.processes` setter, `_AXUIElementCreateApplication/CopyAttributeValue`; plist.json has `NSAudioCaptureUsageDescription` ("real-time music waveform visualizer"), `NSAppleMusicUsageDescription` ("animated artwork"), entitlements `com.apple.security.automation.apple-events` + `temporary-exception.apple-events` for com.spotify.client / com.apple.Music, and `cs.disable-library-validation` (needed for perl to dlopen the adapter framework). Strings also confirm `https://lrclib.net/api/search?track_name=`, `https://spclient.wg.spotify.com/canvaz-cache/v0/canvases`, `https://itunes.apple.com/search?term=`, `http://localhost:26538`.

SURFACES. (1) Closed notch "MusicLiveActivity" (ContentView.swift:1393-1518): left wing = album art square of side `closedHeight-12` (hover: wings grow by 12, outer height +8), right wing = 4..6-bar spectrum (bar 2 pt, gap 2 pt, 14 pt tall, 30 fps real-time or 0.3 s random CA animation) tinted with the album average color gradient, centre = black rect of `max(closedNotchWidth(+8 hover), 96)`; grows to 380 pt during an inline sneak peek with title marquee on the left and artist on the right. (2) Sneak peek on track change (`showSneakPeekOnTrackChange` default true, `enableSneakPeek` default false): standard style = under-notch `music.note` + "title - artist" grey marquee for 1.5 s; inline style = expanding view 3 s with .smooth animation. (3) Open notch standard player (NotchHomeView.swift:225-886): HStack(spacing 12) of AlbumArtView (square, corner radius 13 opened / 4 closed, 1/3 of that for wide art; 36x36 app-icon badge offset (10,10); scale 0.85 when paused; blurred glow texture radius 40 behind, opacity 0.5 playing) and MusicControlsView (title .headline marquee + explicit E badge 14 pt, artist tinted .headline medium, optional lyric line 12 pt, MusicSliderView in a `TimelineView(.animation(minimumInterval: 1/30))` with 8/14 pt track, 11 pt mono time labels, five control slots using 30 pt/40 pt HoverButtons, media-output & AirPlay popovers 240 pt). (4) Minimalistic player (MinimalisticMusicPlayerView.swift): 50 pt art, 12/10 pt text, 24 pt visualizer in a 42 pt block, inline slider 7/11 pt with "-remaining", 36x36 r14 squircle buttons and 54x54 r22 play/pause, exact height formula 50+10+56+(50 lyrics)+padding; "U-shaped" notch-hugging variant pulls art/visualizer up by `notchHeight-4`. (5) Horizontal two-finger swipe on the closed notch or open home skips track / seeks ±10 s with a haptic and a marching-chevron glyph. (6) Floating control overlay window (MusicControlOverlay) beneath the closed notch when `musicControlWindowEnabled` (PRIVATE SkyLightWindow). (7) Lyrics: LRCLIB search → NetEase fallback, LRC parsed, synced with a 0.25 s lead and 50-250 ms adaptive sleep, per-word sweep gradient with 0.06 feather, side panel (280 pt default) or inline line, pinned 1/3/5-line strip under the closed notch (10 pt font). (8) Animated artwork: Apple Music editorial video via MusicKit (public) and Spotify Canvas via spclient (needs sp_dc cookie), played with AVQueuePlayer+AVPlayerLooper muted, shown in the open-notch artwork when `showLiveCanvasInDynamicIsland`. (9) Track-change 3D flip (180° Y rotation .easeInOut 0.45 s, perspective 0.5, debounced 0.6 s) and 0.225 s manual-skip artwork hand-off.

PUBLIC-ONLY REIMPLEMENTATION PATH FOR NOTCHISLAND: use AppleScript (NSAppleScript, public, needs `com.apple.security.automation.apple-events` + NSAppleEventsUsageDescription) for Apple Music and Spotify metadata/commands with DistributedNotificationCenter wake-ups; use the CoreAudio process-tap API (`CATapDescription`, `AudioHardwareCreateProcessTap`, aggregate device; public since macOS 14.2, needs NSAudioCaptureUsageDescription) for the real-time visualizer; use MusicKit (public) for animated artwork; keep the MediaRemote "Now Playing" source optional/behind a flag because it is PRIVATE and shipped only via the BSD-3 `mediaremote-adapter` helper (which NotchIsland may legally bundle, but it still calls a private framework). Everything else (SwiftUI layout, timers, lyrics providers over HTTPS, iTunes Search API, Lottie replacement via SwiftUI animation) is public.

## Playback data model and MusicManager state machine

### Behaviour

The notch always has one 'current track' (title, artist, album, artwork, playing flag, elapsed, duration, playback rate, shuffle, repeat, live-stream flag, advertisement flag, explicit flag, liked flag). Metadata/artwork changes trigger a 3D flip of the artwork; play/pause toggles apply instantly (optimistic) and are reconciled with the source within 2 s; when playback stops the player is considered 'idle' after `waitInterval` (default 3 s) which hides the live activity / auto-hides the open player; position is extrapolated client-side from (elapsedTime, timestampDate, playbackRate) so the slider moves at 30 fps without polling; placeholder metadata ('I'm Handsome'/'Me'/'Self Love', 'Unknown', 'Not Playing') never counts as an active session.

### Layout

No view; see PlaybackState fields at DI/models/PlaybackState.swift:31-48 (bundleIdentifier, isPlaying, title='I'm Handsome', artist='Me', album='Self Love', contentIdentifier?, contentURL?, isExplicit?, currentTime, duration, playbackRate=1, isShuffled, repeatMode(.off=1,.one=2,.all=3), lastUpdated, artwork: Data?, liveArtworkURL: URL?). MusicManager @Published surface: songTitle, artistName, albumArt(NSImage, default heart.fill), albumArtGlowTexture, isPlaying, album, isPlayerIdle, isCurrentTrackExplicit, avgColor(NSColor .white), secondaryColor(.gray), bundleIdentifier, songDuration, elapsedTime, timestampDate, playbackRate, isShuffled, repeatMode, isLiveStream, isAdvertisement, usingAppIconForArtwork, skipGesturePulse, currentLyrics, syncedLyrics, lyricsAvailability, showLyrics, currentLyricIndex, isCurrentTrackLiked(Bool?), canFavoriteCurrentTrack, videoArtworkURL, flipAngle, lastFlipDirection, isTransitioning (MusicManager.swift:569-720). `hasActiveSession` = isPlaying || (title not in {i'm handsome, unknown, not playing} || artist not in {me, unknown}) (MusicManager.swift:584-598).

### Animations

Play-state change: `.smooth(duration: 0.18)` when it matches the optimistic expectation, plain `.smooth` otherwise (MusicManager.swift:942-945, applied via withTransaction at :898-910). Optimistic toggle: `togglePlay()` flips isPlaying immediately with `.smooth(duration:0.18)` then calls controller play/pause; a 2 s recovery task (`optimisticPlaybackRecoveryTimeout = .seconds(2)`, :547) cancels the expectation and forces `updatePlaybackInfo()` if the source never confirmed (:1617-1656); incoming events that contradict the expectation are ignored until the expected state arrives (OptimisticPlaybackTransition :110-130). Artwork flip on any content change: `flipAngle += ±180` with `.easeInOut(duration: 0.45)` (flipAnimationDuration :717, triggerFlipAnimation :1332-1350), direction from last skip direction, cooldown = 0.45+0.15 = 0.6 s so bursts of title/artwork/bundle updates give one flip. Flip rendering: `.rotation3DEffect(.degrees(angle), axis:(0,1,0), anchor:.center, perspective: 0.5)` + `.scaleEffect(x: cos-sign)` so the back face is never mirrored (AlbumArtFlipModifier :2309-2341). Manual next/previous: `beginManualTrackArtworkHandoff()` holds any new artwork for `manualTrackArtworkTransitionDuration = 0.225 s` so the flip is half-way before the image swaps (ManualTrackArtworkHandoff :132-157, :1447-1489). Album art apply: `withAnimation(.smooth) { albumArt = new }` (:1493). Idle: after pause, `Task.sleep(Defaults[.waitInterval])` then `withAnimation { isPlayerIdle = !isPlaying }` (:1431-1445).

### State and timing

Controller selection: on init, after an async `MediaChecker.checkDeprecationStatus()` (runs `perl mediaremote-adapter.pl <fw> <NowPlayingTestClient> test`, helpers/MediaChecker.swift:33-57) the preferred controller is created; if NowPlaying is deprecated and preferred, Apple Music is used; if the preferred one fails to construct, fallback to Apple Music (MusicManager.swift:872-887). Pear Desktop (`com.github.th-ch.youtube-music`) launch/terminate auto-switches to/from YouTubeMusicController (:774-803). `forceUpdate()` is called on every controller swap (:889-895). Lyrics preference changes re-fetch/discard. updateFromPlaybackState order: advertisement → play state → content change (flip, artwork, app icon, video artwork, explicit) → lyrics identity → time/rate/shuffle/repeat/bundle → live-stream → liked → TIDAL modes (every >=2 s) → timestampDate → lyric sync start/stop.

### Data sources and APIs

Controller publishers received on DispatchQueue.main (:859-866). Position estimate: `estimatedPlaybackPosition(at:) = clamp(elapsedTime + (now - timestampDate) * playbackRate, 0, songDuration)` when playing, else min(elapsedTime,duration) (:1513-1519). Live-stream heuristic (:1352-1416): no known duration for >=3 consecutive playing updates → live; or progress>=0.999 observed >=3 times / within 1 s of end with current>=10 s observed >=5 times → live; cleared when duration>10 && remaining>5 or after 4 'release' observations. Advertisement heuristic (:1560-1584): Spotify only; identifier prefix `spotify:ad:` or `/ad/`, or (title present, duration<=120 s, artist+album missing/'unknown', no artwork). Explicit flag: source-provided `isExplicit`, else Spotify embed page scrape `https://open.spotify.com/embed/track/{id}` (parses `"isExplicit":true` or __NEXT_DATA__ contentRating), else iTunes Search `https://itunes.apple.com/search?term={title artist}&media=music&entity=song&limit=15` scored match >=8 (:159-531, :1216-1330); 300-entry caches. Favourites: delegated to controller (`isCurrentTrackFavorited`/`setCurrentTrackFavorited`), keyed by contentIdentifier/contentURL/title+artist+album (:1134-1214); optimistic toggle reverted on failure. App icon fallback artwork when source has none (`AppIconAsNSImage(for: bundleIdentifier)`, :1005-1011). Brand accent: Apple Music pink Color(0.999,0.171,0.331), Spotify green (0,0.857,0.302), Amazon orange (1,0.6,0), others .accentColor (:2302-2304). All public Foundation/AppKit APIs.

### Settings

mediaController: MediaControllerType (default .appleMusic on macOS>=15.4 else .nowPlaying; Constants.swift:1243,1529); waitInterval: Double 3 (stepper 0...10 s, 'Media inactivity timeout'; :1070, SettingsView:3493); showStandardMediaControls: Bool true (:1088); autoHideInactiveNotchMediaPlayer: Bool true (:1089); enableMinimalisticUI: Bool false (:1503); showShuffleAndRepeat: Bool true ('customizable controls', :1071); showMediaOutputControl: Bool true (:1072); musicControlSlots: [MusicControlButton] = [shuffle, trackBackward, playPause, trackForward, repeatMode] (:1084, MusicControlButton.swift:41); musicSkipBehavior: .track|.tenSecond default .track (:1086); coloredSpectrogram: Bool true (:1063); playerColorTinting: Bool true (:1043); sliderColor ('sliderUseAlbumArtColor'): .white|.albumArt|.accent default .white (:1039); colorExtractionMode: .legacy|.vibrant default .vibrant (:1047); lightingEffect: Bool true (:1026); cornerRadiusScaling: Bool true (:1029); parallaxEffectIntensity: Double 6.0 (:1069); spotifySPDCCookie/spotifyAuthAccessToken/... (:1244-1248); cachedMusicLiveActivityPreference/cachedMusicControlWindowPreference: Bool? nil (:1090-1092).

### Dependencies

sindresorhus/Defaults 9.0.3 (MIT) for settings; Combine.

### Implementation notes

Reimplement as an `@MainActor @Observable` NowPlayingStore with a `PlaybackSnapshot` value type, a `MediaSource` protocol (play/pause/toggle/next/prev/seek/shuffle/repeat/isActive/refresh + favouriting), and one active source. Keep the 'anchor + rate' extrapolation model, the 0.18 s optimistic transition with 2 s reconciliation, the 3 s idle debounce, the 0.45 s flip with 0.6 s cooldown and 0.225 s hand-off. Swift 6: all state on MainActor, sources as actors publishing via AsyncStream. ~900 lines.

### Key files

- `DI/managers/MusicManager.swift`
- `DI/models/PlaybackState.swift`
- `DI/MediaControllers/MediaControllerProtocol.swift`
- `DI/models/MusicControlButton.swift`

## Now Playing source via MediaRemote adapter (PRIVATE) and filtered variants (TIDAL, Cider, Amazon Music)

### Behaviour

With 'Now Playing' selected the notch follows whatever app macOS reports as now playing (any app: browsers, VLC, etc.), including artwork, shuffle/repeat, and gets push updates instantly. TIDAL/Cider/Amazon sources show only that app's session and go idle ('Unknown'/'Unknown') when another app takes Now Playing, except TIDAL keeps its state when a browser steals Now Playing while TIDAL's audio process is still outputting.

### Layout

N/A (data source).

### Animations

N/A.

### State and timing

Push-driven; no polling. `isActive()` for NowPlaying always true; filtered variants check NSWorkspace.runningApplications. `updatePlaybackInfo()` is a no-op for these (stream is authoritative).

### Data sources and APIs

PRIVATE: `/System/Library/PrivateFrameworks/MediaRemote.framework` loaded with `CFBundleCreate` + `CFBundleGetFunctionPointerForName` for `MRMediaRemoteSendCommand(Int, AnyObject?)`, `MRMediaRemoteSetElapsedTime(Double)`, `MRMediaRemoteSetShuffleMode(Int)`, `MRMediaRemoteSetRepeatMode(Int)` (NowPlayingController.swift:55-93; AmazonMusicController.swift:43-90 identical). Command ids: play 0, pause 1, togglePlayPause 2, next 4, previous 5 (:115-133); shuffle mode 1=off,3=on (:231); repeat uses RepeatMode raw values 1 off/2 one/3 all, cycling off→all(3)→one(2)→off (:252-254). Metadata stream: child process `/usr/bin/perl <Resources>/mediaremote-adapter.pl <Resources>/MediaRemoteAdapter.framework stream --micros` (:258-307; filtered controllers omit --micros :200-201); stdout JSON lines `{payload:{title,artist,album,duration|durationMicros,elapsedTime|elapsedTimeMicros,timestamp|timestampEpochMicros,shuffleMode,repeatMode,artworkData(base64),playbackRate,playing,parentApplicationBundleIdentifier,bundleIdentifier}, diff:Bool}` (:454-555). The adapter framework (mediaremote-adapter/MediaRemoteAdapter.framework, BSD-3 by Jonas van den Berg) internally uses `MRMediaRemoteRegisterForNowPlayingNotifications`, `MRMediaRemoteGetNowPlayingInfo/Client/ApplicationPID/IsPlaying`, `kMRMediaRemoteNowPlayingInfo*` keys and `MRMediaRemoteSetPlaybackSpeed` (strings dump of the framework binary). Diff semantics: absent key = unchanged; explicit null elapsedTime = position cleared (:480-526). Anchor handling: elapsed+timestamp adopted as a pair; on a play/pause transition without a fresh (<=2 s old, `currentSampleWindow`) sample, the position is frozen (pause) or resumed from the frozen value (play) and re-anchored to 'now' (:368-416). Deprecation probe: `MediaChecker` runs the adapter's `test` function (symbol `_adapter_is_it_broken_yet`) and falls back to Apple Music if MediaRemote is unusable on this macOS (helpers/MediaChecker.swift). Favouriting under Now Playing is routed by bundle id to AppleMusicFavoriting (AppleScript `favorited`/`loved` of current track), SpotifyFavoriting (web API), YouTubeMusicFavoriting (local HTTP), TidalAccessibility (read-only) (:143-217). FilteredNowPlayingController (AmazonMusicController.swift:29) idles with title/artist 'Unknown' when a different source owns Now Playing (:240-260); TidalController overrides `shouldPreservePlaybackState(whenCompetingWith:)` to keep state when the competitor is a browser bundle (Safari, Chrome, Brave, Edge, Firefox, Arc, Vivaldi, Opera, DuckDuckGo, Kagi) and `AudioProcessQuery.isRunningOutput` reports TIDAL's audio process active (TidalController.swift:30-68; public CoreAudio `kAudioHardwarePropertyProcessObjectList`). TIDAL shuffle/repeat/favourite: PRIVATE-ish but public API: Accessibility (`AXUIElementCreateApplication`, `kAXChildrenAttribute`, menu bar Playback menu items checked state, `AXUIElementPerformAction kAXPressAction`), refreshed at most every 2 s (TidalController.swift:162-410, MusicManager.swift:674,1109-1132) — requires Accessibility permission. Cider favourite: `GET/POST http://localhost:10767/api/v1/playback/...` with `apptoken` header (CiderController.swift:86-190). REA: confirmed (see summary).

### Settings

mediaController = .nowPlaying | .tidal | .cider | .amazonMusic; ciderApiToken (Constants.swift:1250).

### Dependencies

Bundled mediaremote-adapter (BSD-3-Clause, github.com/ungive/mediaremote-adapter) — framework + perl script copied into Contents/Resources; requires `com.apple.security.cs.disable-library-validation` (signature.json) so perl can load it.

### Implementation notes

If NotchIsland wants a universal 'Now Playing' source it must either (a) bundle the same BSD-3 adapter + perl bridge (private API, App-Store-incompatible, may break on macOS updates) or (b) restrict to AppleScript/HTTP sources. Recommended: ship AppleScript Apple Music + Spotify by default, optional adapter-based source gated by a setting and a runtime probe. If bundling: spawn `Process` with stdout Pipe, parse JSON lines on a background actor, implement the diff/anchor rules above exactly. ~450 lines for the controller + 250 for the filtered variant.

### Key files

- `DI/MediaControllers/NowPlayingController.swift`
- `DI/MediaControllers/AmazonMusicController.swift`
- `DI/MediaControllers/TidalController.swift`
- `DI/MediaControllers/CiderController.swift`
- `DI/MediaControllers/CiderTokenStore.swift`
- `DI/helpers/MediaChecker.swift`
- `../mediaremote-adapter/mediaremote-adapter.pl`
- `../mediaremote-adapter/MediaRemoteAdapter.framework`

## Apple Music and Spotify sources (AppleScript, public)

### Behaviour

Default source on macOS 15.4+. Metadata refreshes immediately on every player change (distributed notification), after every command (25 ms later), and artwork appears even for streamed Apple Music tracks via the iTunes catalogue. Spotify also shows real artwork (downloaded from the artwork URL), canonical artist names, a Canvas video (if the user pasted an sp_dc cookie), explicit badge and like state.

### Layout

N/A.

### Animations

N/A.

### State and timing

Event driven + post-command refresh (25 ms / 150 ms). No periodic poll; the slider extrapolates between events (lastUpdated = Date() at each AppleScript read, AppleMusicController.swift:261, SpotifyController.swift:203).

### Data sources and APIs

Apple Music: `tell application "Music"` AppleScript executed through `NSAppleScript(source:).executeAndReturnError` on a detached userInitiated task (helpers/AppleScriptHelper.swift:29-32). Info script returns `{player state is playing, name/artist/album of current track, player position, duration, shuffle enabled, song repeat → 1/2/3, raw data of artwork 1}` (AppleMusicController.swift:369-401); artwork <=16 bytes treated as absent (:132). Commands: `play`, `pause`, `playpause`, `next track`, `previous track`, `set player position to X`, `set shuffle enabled to not shuffle enabled`, repeat cycle off→all→one→off (:185-228). Wake-up: `DistributedNotificationCenter` `com.apple.Music.playerInfo` (:167-177). After next/prev: `commandUpdateDelay = 25 ms` then refresh (:146,340-344); shuffle/repeat wait 150 ms (:212,226). Artwork fallback: `https://itunes.apple.com/search?term={title artist}&media=music&entity=song&limit=10`, pick exact title+album match, use `artworkUrl100` with `100x100`→`600x600` (:37-100); single-entry cache. Favourite: `favorited of current track` then fallback `loved` (:415-461). Spotify: `tell application "Spotify"`; info script returns `{player state is playing, name, artist, album, player position, duration(ms→/1000), shuffling, repeating, artwork url, id, spotify url}` (SpotifyController.swift:357-381); repeat only off/all; commands play/pause/playpause/next track/previous track/`set player position to`, `set shuffling to not shuffling`, `set repeating to not repeating` (:124-143); wake-up `com.spotify.client.PlaybackStateChanged` (:83-93); artwork fetched via `ImageService.shared.fetchImageData(from:)` and kept across updates when URL unchanged (:212-275). Canvas (live artwork): POST protobuf to `https://spclient.wg.spotify.com/canvaz-cache/v0/canvases` with Bearer token from `SpotifyAuthManager` (sp_dc cookie → `https://open.spotify.com/api/token` with TOTP computed from secrets fetched at `https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json`; SpotifyAuthManager.swift:36-157) — unofficial, fragile; cache 1 h hit / 5 min miss (:604-614). Entitlement `com.apple.security.temporary-exception.apple-events` lists com.spotify.client and com.apple.Music (signature.json) → REA confirmed.

### Settings

mediaController = .appleMusic | .spotify; spotifySPDCCookie: String "" ; spotifyAuthAccessToken/Expiration/LastValidatedAt; spotifyLibraryClientID (Constants.swift:1244-1248).

### Dependencies

None beyond Foundation.

### Implementation notes

Direct public reimplementation. Use `NSAppleScript` off the main thread (or `OSAScript`), identical scripts (re-author wording), DistributedNotificationCenter async sequences, 25 ms post-command refresh. Skip the Spotify canvas/TOTP machinery (unofficial) unless explicitly wanted. ~500 lines for both.

### Key files

- `DI/MediaControllers/AppleMusicController.swift`
- `DI/MediaControllers/SpotifyController.swift`
- `DI/managers/SpotifyAuthManager.swift`
- `DI/helpers/AppleScriptHelper.swift`
- `DI/managers/ImageService.swift`

## YouTube Music source (th-ch youtube-music desktop app HTTP/WebSocket API)

### Behaviour

When the 'YouTube Music' desktop app (bundle com.github.th-ch.youtube-music, aka Pear Desktop) is running the notch auto-switches to it (even if another source is selected) and controls it; reverts when it quits.

### Layout

N/A.

### Animations

N/A.

### State and timing

WebSocket push, else 2 s poll; `pollPlaybackState()` also fetches repeat/shuffle (Controller:337-345).

### Data sources and APIs

Public HTTP: base `http://localhost:26538` (YouTubeMusicModels.swift:32-37); auth `POST /auth/DynamicIsland` → accessToken (YouTubeMusicNetworking.swift:46); `GET /api/v1/song` → {isPaused, videoId, title, artist, album, elapsedSeconds, songDuration, imageSrc, repeatMode, isShuffled} (:61-66, Models:45-56); commands `POST /api/v1/play|pause|next|previous|shuffle|switch-repeat|seek-to` with Bearer token (YouTubeMusicController.swift:72-93, 347-391); WebSocket `/api/v1/ws?token=` for PLAYER_INFO pushes (Networking:224-236), with reconnect backoff 1...60 s; fallback `Timer` poll every 2.0 s when no socket (`updateInterval: 2.0`, Models:36; Controller:320-335); after a command without socket, 100 ms then refresh (:383). Favourite via local like endpoint (Controller:552-600).

### Settings

mediaController = .youtubeMusic (auto-switch on app launch regardless, MusicManager.swift:774-803).

### Dependencies

None.

### Implementation notes

Optional for NotchIsland; straightforward URLSession + URLSessionWebSocketTask. ~400 lines.

### Key files

- `DI/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift`
- `DI/MediaControllers/YouTube Music Controller/YouTubeMusicNetworking.swift`
- `DI/MediaControllers/YouTube Music Controller/YouTubeMusicModels.swift`
- `DI/MediaControllers/YouTube Music Controller/YouTubeMusicAuthentication.swift`

## Closed-notch Music Live Activity (artwork left wing, visualizer right wing, metadata centre)

### Behaviour

While music is playing (or paused but not yet idle) the closed notch grows two 'wings': the album art on the left, the spectrum on the right; the black centre keeps the notch width. Hovering widens the wings by 12 pt and the whole bar by 8 pt. When a secondary activity (timer, reminder, recording, focus, caps lock, shelf count, extension) is active it takes the right wing and a small round badge appears at the artwork's bottom-right; swapping secondaries cross-fades with a slight scale. Hovering the spectrum (when 'open on hover' is off) blurs it and shows a play/pause glyph; clicking toggles playback with a haptic. On non-notch screens an optional 'title • artist' marquee is shown in the centre.

### Layout

ContentView.swift:1393-1518. Let closedHeight = vm.effectiveClosedNotchHeight; outerHeight = closedHeight + (hover ? 8 : 0); notchContentHeight = hover ? closedHeight : closedHeight-12; wingBaseWidth = notchContentHeight + gestureProgress/2; artworkSize = min(closedHeight-12, wingBaseWidth); centerBaseWidth = max(closedNotchSize.width + (hover?8:0), 96) (closedNotchWidth default 150, Constants.swift:1015); effectiveCenterWidth = inlineSneakPeekActive ? 380 : centerBaseWidth; rightWingWidth = wingBaseWidth unless a secondary overrides (timer: max(base, centerBase*0.38..0.52, base+12..24); recording: clamp(base*0.6, 38, min(base-6,52)); caps-lock label: max(base, centerBase*0.4, base+12); focus/shelf: base; :1554-1636). Tree: HStack(spacing 0) { ZStack(bottomTrailing){ Color.clear.frame(artworkSize²).background(Image(albumArt).resizable().aspectFit.clipShape(RoundedRectangle(r = wide ? 4/3 : 4)))  .clipped().matchedGeometryEffect(id:"albumArt").albumArtFlip ; badge(size = max(13, artworkSize*0.36), offset (0.2*badge, 0.25*badge)) }.frame(wingBaseWidth × notchContentHeight) ; Rectangle.black.frame(effectiveCenterWidth × notchContentHeight).overlay(HStack(top){ inline sneak-peek title marquee (padding.leading 8, frameWidth = (effectiveCenterWidth - closedNotchWidth)/2 - 12, badgeHeight 13, minDuration 0.4) ; Spacer(min closedNotchWidth) ; artist Text lineLimit1 padding.trailing 8 } .clipped()) ; rightWing.frame(rightWingWidth × notchContentHeight) }.frame(notchWidth = wingBase+center+right, notchContentHeight).frame(height: outerHeight). Closed artwork radius constant: `MusicPlayerImageSizes.cornerRadiusInset.closed = 4`, size closed 20×20 nominal (sizing/matters.swift:379-382). Badge: black Circle, SF symbol at 0.5-0.55×badge semibold, shadow black 0.35 r3 y1 (:1639-1687). Spectrum right wing (`SpectrumVisualizer`, :1753-1769): Rectangle filled with `(coloredSpectrogram ? avgColor : .gray).spectrogramGradient()` .frame(width 50) .matchedGeometryEffect(id:"spectrum") masked by AudioVisualizerView.frame(width: barCount*4, height: 12). Hover overlay (:1779-1799): blur 2.4, RoundedRectangle r8 black 0.24 (0.02 idle), play/pause SF 16 semibold white 0.98, padding h14 v6. Text colour in centre = coloredSpectrogram ? avgColor : .gray. Standard sneak-peek row under the notch (:1188-1198): HStack{ Image(music.note); MarqueeText(title + " - " + artist, gray, minDuration 1) } .foregroundStyle(.gray).padding(.bottom 10). Minimalistic closed variant (components/MinimalisticMusicView.swift:24-126): same three columns; centre VStack(center, spacing 2) title 12 semibold (coloured avg or gray) + artist 10 regular + optional lyric 11 semibold; art side = closedHeight-12 (hover: closedHeight), radius wide?4:12; visualizer width barCount*4 height 12.

### Animations

Secondary swap: `.animation(.smooth(duration:0.25), value: secondary.id)` (:1517) and `closedLiveActivitySwapTransition` = asymmetric(insertion: opacity+scale 0.965 with .spring(response 0.34, dampingFraction 0.88); removal: opacity+scale 0.92 with .smooth(0.22)) (:382-391). Badge: `.contentTransition(.symbolEffect(.replace))`, `.transition(.opacity.combined(with:.scale))`. Hover play/pause overlay: `.smooth(duration:0.16)` on hover, `.smooth(0.2)` on isPlaying (:1508,1798-1799). Shelf count: `.contentTransition(.numericText())` + `.smooth(0.3)`. Recording badge pulses: scale 1.2 / opacity 0.7 `.easeInOut(0.8).repeatForever(autoreverses)` (PulsingModifier.swift:26-30). Artwork flip as in MusicManager. matchedGeometryEffect ids "albumArt" and "spectrum" morph into the open player (namespace in ContentView:266).

### State and timing

Shown when `isClosedMusicPairingEligible(notchState == .closed, hasActiveMusicSnapshot (isPlaying || (!isPlayerIdle && has title/artist)), musicLiveActivityEnabled, closedMusicContentEnabled (= enableMinimalisticUI || showStandardMediaControls), !hideOnClosed, !isLocked, !deferredAfterUnlock)` (ContentView:329-335, 1072-1079, helpers/ClosedMusicPairingVisibility.swift). Priority in the closed-notch switch (ContentView:1109-1176): battery HUD > inline HUD > caps lock > music live activity > timer > reminder > recording > download > LocalSend > DND > privacy > extension > shelf > idle face > header. When idle (after waitInterval) and `showNotHumanFace` the face animation replaces it.

### Data sources and APIs

MusicManager published state; AudioVisualizerView; Defaults. Public.

### Settings

musicLiveActivityEnabled (@AppStorage, default true; DynamicIslandViewCoordinator.swift:128) — cached into `cachedMusicLiveActivityPreference` and forced false when both showStandardMediaControls and enableMinimalisticUI are off (DynamicIslandApp.swift:1743-1779); showSongMetadataInClosedNotch: Bool false (Constants.swift:1644); useMusicVisualizer: Bool true (:1044); visualizerBarCount: Int 4 (picker 4/5/6; :1045, SettingsView:3520); coloredSpectrogram: Bool true; openNotchOnHover: Bool true (:997) — the play/pause overlay only exists when this is false; enableHaptics: Bool true (:996).

### Dependencies

None.

### Implementation notes

Port the width arithmetic verbatim (it is layout math, not code). Use `@Namespace` + matchedGeometryEffect for art and spectrum. Pairing eligibility helper is a pure function (helpers/ClosedMusicPairingVisibility.swift:19-35). ~350 lines including badge/secondary plumbing (NotchIsland can start with secondary = nil).

### Key files

- `DI/ContentView.swift`
- `DI/helpers/ClosedMusicPairingVisibility.swift`
- `DI/components/MinimalisticMusicView.swift`
- `DI/sizing/matters.swift`
- `DI/components/Live activities/PulsingModifier.swift`
- `DI/extensions/NSImage+Extensions.swift`

## Sneak peek on playback/track change and expanding (inline) view

### Behaviour

Optional. When a track starts (play state becomes playing with real metadata) or changes while playing, the closed notch briefly announces it. 'Default' style: a grey music-note + 'Title - Artist' marquee line appears under the closed notch for 1.5 s. 'Inline' style: the closed notch widens to 380 pt for 3 s and shows the title (coloured, marquee) on the left and the artist on the right of the notch. Ads never trigger it; starting an ad dismisses any visible peek.

### Layout

Standard style row: ContentView.swift:1188-1198 (HStack{ Image(systemName:"music.note"); GeometryReader{ MarqueeText(title+" - "+artist, textColor .gray, minDuration 1, frameWidth geo.width) } }.foregroundStyle(.gray).padding(.bottom,10)). Inline style: handled inside MusicLiveActivity centre overlay (:1451-1468) with effectiveCenterWidth 380 (:1415); title via MusicTitleMarqueeView(badgeHeight 13, minDuration 0.4, padding.leading 8); artist Text lineLimit(1) truncation .tail padding.trailing 8; colour = coloredSpectrogram ? avgColor : .gray; opacity 1 only while expandingView.show && type == .music && sneakPeekStyles == .inline.

### Animations

toggleSneakPeek writes the struct inside `withAnimation(.smooth(duration: 0.3))` (DynamicIslandViewCoordinator.swift:373); hide after `sneakPeekDuration` (music default 1.5 s; timer 10 s; reminder = reminderSneakPeekDuration 5 s) via Task.sleep then `withAnimation { show=false }` (:383-400). toggleExpandingView uses `withAnimation(.smooth)` (:419) and auto-hides after `autoHideDuration ?? 3` s (:430-447). The notch width change itself animates with the global notch open/close animation (core subsystem).

### State and timing

Standard: 1.5 s. Inline: 3 s. Both reset to defaults after hide (sneakPeekDuration = 1.5).

### Data sources and APIs

MusicManager.updateSneakPeek (MusicManager.swift:1530-1543): requires !isAdvertisement && (showStandardMediaControls || enableMinimalisticUI) && isPlaying && enableSneakPeek; standard → coordinator.toggleSneakPeek(status:true, type:.music); inline → coordinator.toggleExpandingView(status:true, type:.music). Triggered at :947-949 (play state → playing with title&artist) and :1032-1034 (content change while playing, gated by showSneakPeekOnTrackChange). Dismissed at :1546-1553 when an ad starts. Public.

### Settings

enableSneakPeek: Bool false (Constants.swift:1065); sneakPeekStyles: SneakPeekStyle .standard ('Default') | .inline (:1066, Picker 'Sneak Peek Style' SettingsView:3484); showSneakPeekOnTrackChange: Bool true (:1067); enableSystemHUD: Bool true (:1400) — music/timer/reminder/bluetoothAudio bypass this gate (Coordinator:346-358).

### Dependencies

None.

### Implementation notes

Model as two coordinator structs (`SneakPeek{show,type,value,icon,title,subtitle,accentColor,styleOverride,targetScreenName}`, `ExpandedItem{show,type,value,autoHideDuration}`) with didSet-scheduled hide tasks. ~120 lines.

### Key files

- `DI/DynamicIslandViewCoordinator.swift`
- `DI/managers/MusicManager.swift`
- `DI/ContentView.swift`

## Audio visualizer: fake spectrum, real-time CoreAudio process tap, Lottie fallback

### Behaviour

4-6 thin rounded 'candles' bounce next to the artwork. Default: random bounce while playing, collapsed to 20-35 % when paused. With 'Enable real-time waveform' (Beta, needs Audio Capture permission) the candles follow six frequency bands of the actual output of the music app (Apple Music, Spotify, Amazon, Cider, Safari, TIDAL, Plexamp, Roon, Audirvana, Vox). If 'useMusicVisualizer' is off a looping Lottie animation (default a remote lottiefiles JSON, or a user-picked .json) is shown instead. The same real-time bands drive a scrubbable waveform that replaces the slider track on hover (open player).

### Layout

Bars: barWidth 2, spacing 2, totalHeight 14, count = Defaults[.visualizerBarCount]; each bar a CAShapeLayer rounded rect (radius 1) white, anchored at its centre (MusicVisualizer.swift:49-72; RealTimeAudioSpectrum.swift:50-73). Hosted in a `Rectangle` filled with the album gradient and masked by the bar view at frame (barCount*4 × 12) closed / (barCount*4 × 16) minimalistic open (ContentView:1758-1767; MinimalisticMusicPlayerView:756-766). Gradient: `spectrogramGradient()` = LinearGradient top→bottom [color, hue+180°] in vibrant mode, or `color.gradient` in legacy (NSImage+Extensions.swift:507-538). Waveform scrubber (RealTimeWaveformScrubberView.swift): `WaveformShape` mirrors the 6 magnitudes (12 points), cubic curves, thickness = max(minHeight, height*clamp(mag*1.5)); background gray 0.3, foreground colour/gradient opacity 0.8 masked to progress; frame height trackHeight*3.5, offset y trackHeight*0.2 (NotchHomeView:1340-1348).

### Animations

Fake spectrum: Timer every 0.3 s adds `CABasicAnimation(transform.scale.y)` from presentation value to random 0.35...1.0, duration 0.3, autoreverses, fillMode forwards, preferredFrameRateRange 24 fps (MusicVisualizer.swift:85-110); reset scale 0.35 when paused. Real-time: Timer 1/30 s sets `CATransform3DMakeScale(1, max(0.2, min(1, mag*1.5+0.2)), 1)` with CATransaction actions disabled (RealTimeAudioSpectrum.swift:87-118); reset 0.2 when paused. Display smoothing in AudioTap: 30 Hz timer, `display += (target-display)*0.4` (AudioTap.swift:147-157). Waveform scrubber: 60 Hz timer, EMA `0.85*old + 0.15*new`, `withAnimation(.linear(1/60))` on an `AnimatableVector` (RealTimeWaveformScrubberView.swift:42-70).

### State and timing

Fake: 0.3 s timer / 0.3 s autoreversing animations. Real: audio thread → 512-sample blocks → 30 Hz UI timer. Tap restart debounce 0.5 s.

### Data sources and APIs

PUBLIC CoreAudio process-tap API (macOS 14.2+): enumerate `AudioProcessQuery.processObjectIDs()` and bundle ids, match targets by prefix (`com.tidal.desktop.player` → TIDAL) (AudioTap.swift:91-106,129-141,194-233); `CATapDescription(processes:, isMixdown=true, isMono=true)`, `AudioHardwareCreateProcessTap`, read `kAudioTapPropertyUID`, `AudioHardwareCreateAggregateDevice` with `kAudioAggregateDeviceIsPrivateKey = true` and `kAudioAggregateDeviceTapListKey = [[kAudioSubTapUIDKey: uid]]` named 'Atoll_Virtual_Tap', `AudioDeviceCreateIOProcID` + `AudioDeviceStart` (:248-330); Spotify is skipped while the default output is Bluetooth (AirPods AVRCP conflict, :181-209,333-339). DSP: C++ `AudioProcessor` (AudioProcessor.hpp/.cpp) block 512 samples @48 kHz, six vDSP biquads: LP 150 Hz Q0.707, BP 400 Q0.40, BP 1000 Q0.60, BP 2500 Q0.60, BP 5000 Q0.85, HP 8000 Q0.707; per band RMS (vDSP_rmsqv) × gains {3,4.5,6,9,14,24} clamped to 1; asymmetric envelope attack 0.85 / release 0.40; lock-free atomics read by the UI (Accelerate, public). Lifecycle: start at launch if enableRealTimeWaveform, stop/start on the setting; restart (debounced 0.5 s, 0.1 s teardown gap) 2 s after a target app launches, on target termination, and on output-route change (DynamicIslandApp.swift:218-264,776-798; AudioTap.swift:361-384). REA: `_AudioHardwareCreateProcessTap`, `_AudioHardwareCreateAggregateDevice`, `CATapDescription.processes` present in nm; NSAudioCaptureUsageDescription in Info.plist. Lottie: airbnb/lottie-spm + jasudev/LottieUI, default remote JSON `https://assets9.lottiefiles.com/packages/lf20_mniampqn.json` loop speed 1 (LottieAnimationView.swift:29-43) — REA confirms Lottie.framework is linked. metal/visualizer.metal (trivial passthrough vertex/fragment) compiled into default.metallib but no Swift call site in the music views found (likely unused legacy).

### Settings

useMusicVisualizer: Bool true (Constants.swift:1044); visualizerBarCount: Int 4 (4/5/6; :1045); enableRealTimeWaveform: Bool false (:1064); enableWaveformScrubber: Bool true (:1046); coloredSpectrogram: Bool true (:1063); colorExtractionMode: .vibrant (:1047); customVisualizers: [CustomVisualizer{UUID,name,url,speed}] [], selectedVisualizer: nil (:1048-1049).

### Dependencies

lottie-spm (Apache-2.0), LottieUI (MIT) — only for the optional Lottie mode.

### Implementation notes

Public reimplementation: Swift-only is fine (replace C++ with vDSP from Accelerate in Swift, or a tiny C target in the package). Keep the 6 biquad bands, 512-sample blocks, 0.85/0.40 envelope, 30 Hz UI smoothing 0.4. Render bars with SwiftUI `Canvas` or CAShapeLayers in an NSViewRepresentable (30 fps timer). Skip Lottie; offer a SwiftUI fallback. Requires `NSAudioCaptureUsageDescription`. ~600 lines.

### Key files

- `DI/audio/AudioTap.swift`
- `DI/audio/AudioProcessor.hpp`
- `DI/audio/AudioProcessor.cpp`
- `DI/audio/AudioBridge.h`
- `DI/audio/AudioBridge.mm`
- `DI/audio/RealTimeAudioSpectrum.swift`
- `DI/audio/AudioVisualizerView.swift`
- `DI/components/Music/MusicVisualizer.swift`
- `DI/components/Music/RealTimeWaveformScrubberView.swift`
- `DI/components/Music/LottieAnimationView.swift`
- `DI/metal/visualizer.metal`
- `DI/DynamicIslandApp.swift`

## Open-notch standard music player (NotchHomeView: MusicPlayerView / AlbumArtView / MusicControlsView / MusicSliderView / CustomSlider / HoverButton)

### Behaviour

In the open notch's Home tab: large album art on the left (click opens the source app; dimmed+shrunk when paused; parallax tilt on hover; app icon badge bottom-right; blurred colour glow behind it when playing), title (marquee, explicit 'E' badge), artist tinted with the album colour, optional current lyric line, a progress slider that thickens on drag and can turn into a live waveform on hover, time labels, and a row of five configurable controls (shuffle, previous, play/pause, next, repeat by default; or seek ±10 s, lyrics, like, media output, AirPlay). While a volume/brightness/backlight HUD is showing in the open notch, the control row is replaced by a slider with icons. Hidden entirely when nothing has played yet (auto-hide) and replaced by the calendar/mirror layouts; with lyrics enabled and the calendar hidden a side lyrics panel appears to the right.

### Layout

NotchHomeView.swift:225-237 MusicPlayerView = HStack(alignment:.top, spacing:12){ AlbumArtView ; MusicControlsView.frame(maxWidth:.infinity, .leading) }. Home content padding 8 (:990); open notch size 640(min; 690 for 5 tabs, 770 for 6)×200 (sizing/matters.swift:69-75,138-142); opened corner radii top 19 / bottom 24 (:199). AlbumArtView (:323-439): ZStack(bottomTrailing){ glow (if lightingEffect): GeometryReader{ Color.clear.background(Image(albumArtGlowTexture).resizable().fill).mask(RadialGradient [.white, .white 0.7, .clear] center, endRadius width*0.65).scaleEffect(x1.3,y1.4).rotationEffect(92°).opacity(playing ? 0.5 : 0; canvas: 0.62/0.18).shadow(avgColor 0.16 r14; canvas 0.24 r22) }.aspectRatio(1,.fit) ; Button(openMusicApp){ ZStack(bottomTrailing){ Color.clear.aspectRatio(1).overlay(DynamicIslandArtworkSourceView(cornerRadius, .fit)).matchedGeometryEffect("albumArt").clipped() ; appIconOverlay 36×36 scaledToFill offset(10,10) zIndex 2 }.albumArtFlip.parallax3D().padding(.bottom,-5) }.plain.scaleEffect(playing ? 1 : 0.85) ; dark overlay Rectangle black opacity(playing?0:0.8).blur(50) }. Artwork corner radius: cornerRadiusScaling ? (wide ? 13/3 : 13) : (wide ? 4/3 : 4) where `MusicPlayerImageSizes.cornerRadiusInset = (opened 13, closed 4)`, size opened 90×90 (sizing/matters.swift:379-382); RoundedRectangle style .continuous (:219). MusicControlsView (:441-470): VStack(.leading){ songInfoAndSlider (GeometryReader VStack spacing 4 { songInfo; musicSlider }.padding(.top 10).padding(.leading 5)) ; controlHUDRow or playbackControls }. songInfo (:486-548): MusicTitleMarqueeView(font .headline, white, badgeHeight 14) ; MarqueeText(artist, .headline, .medium, colour = playerColorTinting ? avgColor.ensureMinimumBrightness(0.6) : .gray) ; if enableLyrics && showCalendar: InstrumentalBreakNotes(10 regular, white 0.7) or lyric MarqueeText(.system(12), white 0.7, minDuration 0.35).padding(.top 2). musicSlider (:555-576): TimelineView(.animation(minimumInterval: 1/30, paused: !playing || live || rate<=0)) { MusicSliderView(...).padding(.top 5).frame(height 36) }. MusicSliderView stacked (:1106-1120): VStack(spacing 6){ sliderCore.frame(height max(8,14)) ; HStack{ Text(elapsed) Spacer Text(duration) }.font(.system(11,.medium).monospacedDigit()).foregroundColor(timeLabelColor) }; inline variant: HStack(spacing 6){ Text 36 pt leading; slider; Text 42 pt trailing }; live: `LiveStreamProgressIndicator` (two 3 pt capsule rules fading 0.5→0.16 + 'LIVE' 12 rounded semibold tracking 0.6; LiveStreamProgressIndicator.swift). Slider tint: sliderColor .albumArt → avgColor.ensureMinimumBrightness(0.6), .accent → .accentColor, .white → .white (:1211-1223); time label colour = playerColorTinting ? tinted : .gray. `hasUsableDuration` = finite, >0, <= 86400 else '--:--' (:1241-1247). CustomSlider (:1298-1404): track gray 0.3 height = dragging ? 14 : 8, corner height/2, filled Rectangle in tint; thumbSize 12 (unused visual); on hover with real-time waveform enabled → RealTimeWaveformScrubberView; DragGesture(minimumDistance 0) sets value from x/width, onEnded calls onValueChange + lastDragged. playbackControls (:578-585): HStack(spacing 8) of 5 slots centred; HoverButton (components/HoverButton.swift:46-92): size 40 (.large, play/pause) or 30 (.medium); Capsule gray 0.2 on hover; icon font .largeTitle or .body; shuffle/repeat/lyrics/like active colour = brandAccentColor; repeat icon 'repeat' / 'repeat.1'; play icon pause.fill / stop.fill (live) / play.fill. Control HUD row (:605-654): HStack(spacing 10){ left icon 16 semibold 22×22 ; CustomSlider(0...1, white, thumb 10, track 4/7).frame(h 7) in 22 ; right icon }. Media output / AirPlay popovers: 240 pt wide, padding 16, volume section (28 pt circle mute button, Slider tint accent, 'Output volume' caption + %), device list rows padding v6 h8, selected background primary 0.12 r8, max height 240/300 (:1529-1733). Side lyrics panel: LyricsSidePanelView width = lyricsPanelWidth (default 280), offset lyricsPanelOffset, header 'Lyrics' .headline tinted + 11 pt pin button, background black 0.3 r4 (:239-321); required notch width = 380 player + panel + 20 + |offset| + (mirror ? 240) + 40 (sizing/matters.swift:31-67).

### Animations

Artwork pause shrink: scaleEffect 1 → 0.85 and dark overlay opacity 0 → 0.8 animate with whatever drives isPlaying (.smooth 0.18). App icon badge: `.transition(.scale.combined(with:.opacity).animation(.bouncy.delay(0.3)))` (:435). Parallax (extensions/View+Parallax3D.swift:51-75): onContinuousHover → `.interactiveSpring(response 0.1, dampingFraction 0.5)` while moving, `.spring(response 0.35, dampingFraction 0.6)` on exit; rotation3DEffect degrees = offset.height*intensity (X axis) and offset.width*-intensity (Y axis), intensity default 6. Slider: `.animation(.bouncy.speed(1.4), value: dragging)` for the 8→14 swell, hover `.easeInOut(0.2)`, saturation/opacity `.easeOut(0.2)`; slider value writes use a Transaction with `disablesAnimations = true` so the 30 fps timeline never animates (:1098-1104); snaps to true position on pause (:1084-1090). HoverButton hover `.smooth(0.3)`; press effects: nudge `.spring(0.2, 0.55)` then back `.spring(0.28, 0.72)`; wiggle ±angle `.spring(0.18, 0.5)` then `.spring(0.32, 0.72)` (HoverButton.swift:96-150); SF `.symbolEffect(.wiggle.byLayer, options:.nonRepeating)` on macOS 15 for seek buttons; contentTransition .symbolEffect(.replace) for play/pause. SkipTrackGlyph (components/Music/SkipTrackGlyph.swift): three play.fill triangles (glyphSizeRatio 0.88, stepRatio 0.52, frame size*1.5 × size) marching one step with `.easeOut(duration 0.26)`; leading fades out, spare fades in; phase accumulates so rapid presses chain. Lyric line swap: asymmetric move bottom→top + opacity, `.easeInOut(0.32)` (:507-544). HUD slider glide `.easeOut(0.18)` (:674). Main content transition: `.opacity.animation(.smooth.speed(0.9)).combined(with:.move(edge:.top))`, blur 30 when closed (:987-989).

### State and timing

Slider ticks at 30 fps only while playing and not live; onChange(currentDate) updates value unless dragging or within 1 s of the last drag (`timestampDate.timeIntervalSince(lastDragged) > -1`, :1081). Media-output popover keeps the notch open via `vm.setMediaOutputPopoverActive(token)`; own-volume changes suppress the system volume HUD for 1.5 s (:1795-1813).

### Data sources and APIs

MusicManager; SystemVolumeController/SystemBrightnessController/SystemKeyboardBacklightController (CoreAudio `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` 'vmvc', `kAudioDevicePropertyVolumeScalar/Mute`; IOKit/DisplayServices for brightness — managers/SystemMediaControllers.swift, public CoreAudio; brightness part is in the HUD subsystem); AudioRouteManager (public CoreAudio device enumeration `kAudioHardwarePropertyDevices`, transport types, `kAudioHardwarePropertyDefaultOutputDevice`); AppleMusicAirPlayManager (AppleScript `AirPlay devices`, `selected of`, `sound volume of` — public). AVQueuePlayer/AVPlayerLooper for canvas video (:52-95).

### Settings

showStandardMediaControls true; autoHideInactiveNotchMediaPlayer true (player shown iff showStandardMediaControls && (!autoHide || hasActiveSession), NotchHomeView:908-910); showShuffleAndRepeat true; musicControlSlots default layout, minimal layout [none, back, play, next, none] when custom controls off, or [none, seekBack, play, seekFwd, none] for tenSecond (:743-755); showMediaOutputControl true; musicSkipBehavior .track; sliderColor .white; playerColorTinting true; lightingEffect true; cornerRadiusScaling true; parallaxEffectIntensity 6.0; enableLyrics false; showCalendar true (:1036); lyricsPanelWidth 280; lyricsPanelOffset 0; showLiveCanvasInDynamicIsland false (:1515); enableRealTimeWaveform false; enableWaveformScrubber true; enableSystemHUD true; enableVolumeHUD true; openNotchWidth 640.

### Dependencies

Defaults; Pow (EmergeTools, MIT) is in the package list but not used in these files.

### Implementation notes

Reimplement with SwiftUI: a `TimelineView(.animation(minimumInterval: 1/30, paused:))` driving a plain slider whose value is computed from the store's anchor; write slider state inside `Transaction(disablesAnimations:true)`. Keep sizes: art 90 pt r13, HStack spacing 12, slider 8/14 pt, labels 11 pt mono, buttons 30/40 pt, controls spacing 8. Avoid the private AX/AirPlay bits initially. ~1,000 lines for player + slider + buttons + popovers.

### Key files

- `DI/components/Notch/NotchHomeView.swift`
- `DI/components/HoverButton.swift`
- `DI/components/Music/SkipTrackGlyph.swift`
- `DI/components/Music/LiveStreamProgressIndicator.swift`
- `DI/components/Notch/LikeTrackControl.swift`
- `DI/extensions/View+Parallax3D.swift`
- `DI/sizing/matters.swift`
- `DI/managers/AudioRouteManager.swift`
- `DI/managers/AppleMusicAirPlayManager.swift`
- `DI/managers/SystemMediaControllers.swift`

## Minimalistic open player (MinimalisticMusicPlayerView) and its 'Nothing Playing' state

### Behaviour

When 'Minimalistic UI' is on, the open notch is only a compact player: 50 pt artwork, title/artist, small visualizer on the right, a full-width thin progress bar with elapsed on the left and '-remaining' on the right, and a centred row of rounded-square buttons (36 pt; 54 pt play/pause). Optional two-line lyric with a note glyph below, optional timer countdown (56 pt digits) and reminder rows. With the battery indicator hidden on a notched screen the layout 'hugs' the notch: artwork and visualizer are pulled up beside the physical notch and the text sits below it. When nothing has played: a 'music.note.slash' 24 pt light + 'Nothing Playing' 12 pt medium grey. In Dynamic Island (non-notch pill) mode the open size is 340×144.

### Layout

MinimalisticMusicPlayerView.swift:48-160. Flat header (:76-125): GeometryReader height 50: HStack(center, spacing 10){ MinimalisticAlbumArtView 50×50 ; VStack(.leading, spacing 1){ MusicTitleMarqueeView(.system(12,.semibold), white, badgeHeight 13) ; artist .system(10) tinted/gray lineLimit1 }.frame(width textWidth = W-50-10-(viz ? 42+10 : 0)) ; ZStack{ visualizer.frame(width 24) }.frame(width 42) }. progressBar padding.top 6 (4 in hugging mode) (:132-133): MusicSliderView(labelLayout .inline, trailingLabel .remaining, restingTrackHeight 7, draggingTrackHeight 11) in TimelineView 1/30 (:780-805). playbackControls padding.top 4 then 2: HStack(spacing 10) of slots (:819-827). controlHUDRow height 60 with 22×22 icons and slider 4/7 (:847-897). lyricsView padding.top 10: HStack(spacing 6){ music.note 12 semibold white 0.7 ; Text(line) 12 semibold white 0.88 lineLimit 2 }.padding(.horizontal 6).frame(maxHeight 40) (:460-488). Outer padding: horizontal 12 (−4 in DI mode), top 6 / 10 hugging / 14 DI, bottom baselineMinimalisticBottomPadding / 10 / 14 (:153-155). Height formula (:281-325): 50 + (6+4) + (54+2) + (lyrics ? 10+40) + (timer ? 94) + reminders + top(14 DI / 15) + bottom(14 DI / baseline); hugging: 26 + 8 + 56 + ... + 10 + 10. Base open size minimalistic 420×180 (+50 lyrics; sizing/matters.swift:163-165), DI mode 340×144 (:175-181); minimalistic opened corner radius 35/35 (:200). Hugging header (:333-395): albumArtSize 50, visualizerWidth 24, pullUp = max(notchHeight-4, 20); art HStack offset y -pullUp; visualizer HStack trailing with 12 pt spacer offset y -pullUp+(50-16)/2; text VStack padding.leading 60 offset y 50-pullUp-28; frame height 26. MinimalisticAlbumArtView (:1231-1303): radius wide ? 4 : 12 (not scaled); glow = same artwork .fill scaled 1.04×1.05 rotated 92° blur 14 opacity min(0.28, 1-max(brightness,0.3)) (canvas 0.35/0.12) shadow avgColor 0.08 r4; button opacity playing ? 1 : 0.4, scale 1 : 0.85, flip + parallax. Buttons (MinimalisticSquircircleButton :1307-1473): frame 36×36 r14 continuous, icon .system(18, .medium) white 0.85 (active = brand accent); play/pause 54×54 r22 icon 26 semibold white; hover background white 0.18. Nothing-playing (:49-73): VStack(spacing 8){ music.note.slash .system(24,.light) gray ; 'Nothing Playing' .system(12,.medium) gray } centred + timer/reminder sections. Timer block: name marquee 16 semibold + countdown 'SF Pro Display' 56 monospaced digits (:414-449).

### Animations

Height changes `.smooth(duration:0.3)` keyed on a signature (:73,158,261-267). Timer section `.smooth(0.25)`; reminders `.easeInOut(0.18)`; lyric swap `.smooth(0.32)` with move/opacity asymmetric transition. Button press: nudge ±8 pt `.spring(0.16, 0.72)` then `.spring(0.26, 0.8)` after 0.12 s; wiggle ±11° `.spring(0.18, 0.52)` then `.spring(0.32, 0.76)` after 0.18 s; hover `.easeOut(0.18)`; symbol effects .replace / .bounce / .wiggle.byLayer nonRepeating (:1380-1453). TypingLyricView (unused by the main body but defined :164-219) types characters every 30 ms / playbackRate.

### State and timing

Same 30 fps slider; ads suppress the lyrics row (`shouldReserveLyricsSpace = enableLyrics && !isAdvertisement`, :272-274).

### Data sources and APIs

Same as standard player. Public.

### Settings

enableMinimalisticUI false; showMinimalisticBatteryIndicator true (Constants.swift:1175); enableLyrics; timer/reminder keys (other subsystems); musicControlSlots/showShuffleAndRepeat/musicSkipBehavior as above.

### Dependencies

Defaults.

### Implementation notes

Second layout of the same store. Keep the exact height formula and the 50/42/24 header budget so the visualizer centres above the '-00:00' label. ~700 lines.

### Key files

- `DI/components/Notch/MinimalisticMusicPlayerView.swift`
- `DI/sizing/matters.swift`

## Horizontal music gestures and skip press effects

### Behaviour

A horizontal two-finger scroll/swipe over the closed notch (when 'open on hover' is off) or over the open Home tab skips to the next/previous track (or seeks ±10 s when 'musicGestureBehavior' is ±10 Seconds), fires a haptic, and animates the matching button (chevrons march / seek icon wiggles). Reverse direction available. Seeking past the ends of the track wraps to previous/next track.

### Layout

No own view; pulses the HoverButton / squircle buttons via `skipGesturePulse` tokens (NotchHomeView.swift:870-885; MinimalisticMusicPlayerView.swift:1084-1099; MusicControlOverlay.swift:315-335).

### Animations

`handleSkipGesture` fires once per gesture when |translation| > gestureSensitivity (default 200) (ContentView.swift:2650-2676); during the drag the closed notch wings widen by `gestureProgress = translation/sensitivity*20` (:2600,2628) which feeds `wingBaseWidth` (+gestureProgress/2). Button feedback as in the player sections (SkipTrackGlyph .easeOut 0.26; nudge/wiggle springs).

### State and timing

One skip per gesture (skipGestureActiveDirection latch until phase .ended); blocked while locked, while any popover is open, while hovering the calendar, or during a vertical scroll gesture (:2678-2689).

### Data sources and APIs

NSEvent scroll phases (core gesture subsystem); MusicManager.handleSkipGesture (MusicManager.swift:1706-1734): requires enableHorizontalMusicGestures and (!isPlayerIdle || bundleIdentifier != nil); `.track` → next/previous (sets lastFlipDirection); `.tenSecond` → seek(by: ±10) (:1684-1704: if current <= 10 s backward → previousTrack; if remaining <= 10 s forward → nextTrack; live streams ignore). Haptics via NSHapticFeedbackManager (public).

### Settings

enableGestures true (Constants.swift:1054); enableHorizontalMusicGestures true (:1057); musicGestureBehavior .track|.tenSecond default .track (:1058); gestureSensitivity 200 (:1056); reverseSwipeGestures false (:1059); enableHaptics true (:996); openNotchOnHover true (:997).

### Dependencies

None.

### Implementation notes

Reuse NotchIsland's existing gesture pipeline; add a 'pulse' token to the store so buttons can animate externally. ~150 lines.

### Key files

- `DI/ContentView.swift`
- `DI/managers/MusicManager.swift`

## Floating media control overlay window under the closed notch (MusicControlOverlay)

### Behaviour

Optional ('Show floating media controls'): while music plays (and for 5 s after a pause) a small black rounded bar with previous / play-pause / next floats just below the closed notch on the right, with hover highlights and the same nudge/wiggle feedback; it mirrors the skip behaviour setting (track vs ±10 s).

### Layout

MusicControlOverlay.swift:22-165: buttonSide = clamp(notchHeight*0.94, max(30, notchHeight*0.8), max(notchHeight+2, 32)); playPauseSide = min(buttonSide+8, notchHeight+4); buttonCornerRadius = max(cornerRadius-8, buttonSide*0.28); window corner = max(cornerRadius-6, 12); HStack(spacing 18){ back; play; next }.padding(.vertical max(8, notchHeight*0.12)).padding(.horizontal 18).frame(height notchHeight).frame(minWidth buttonSide*3.2).background(RoundedRectangle black). Icon font = min(w,h)*0.48 semibold; disabled opacity 0.35 vs 0.9. Metrics passed from ContentView:2933-2942: notchHeight = max(closedNotchSize.height, effectiveClosedNotchHeight), notchWidth = closedNotchWidth + (hover?8:0), rightWingWidth = closedHeight-(hover?0:12)+gestureProgress/2, cornerRadius = closed bottom radius (14), spacing 36. Initial window 240×68 (MusicControlWindowManager.swift:41).

### Animations

`.smooth(0.2)` on isPlaying / skip behaviour / enabled; button nudge/wiggle springs identical to the minimalistic buttons (MusicControlOverlay.swift:263-294); hover `.easeOut(0.18)`.

### State and timing

5 s post-pause grace; 0.24 s resume delay; suppressed during notch open/close transitions.

### Data sources and APIs

Presented through `FlyoutWindowPresenter` on top of `SkyLightWindow` (Lakr233/SkyLightWindow — a PRIVATE SkyLight/CGS window-level helper used to float above the menu bar/notch area). Visibility: shown while playing; after pause kept for `musicControlPauseGrace = 5 s` (ContentView.swift:306,2734-2783); resume delay 0.24 s (:307); hidden when standard controls are off, locked, or the notch opens.

### Settings

musicControlWindowEnabled: Bool false (Constants.swift:1087); cachedMusicControlWindowPreference; requires musicLiveActivityEnabled && showStandardMediaControls (SettingsView:3360-3363).

### Dependencies

SkyLightWindow (private CGS APIs; license unverified).

### Implementation notes

NotchIsland can use a normal borderless NSPanel at `.statusBar`/`.screenSaver` level positioned under the notch — public — and keep the same geometry/timing. ~300 lines.

### Key files

- `DI/components/Music/MusicControlOverlay.swift`
- `DI/managers/MusicControlWindowManager.swift`
- `DI/managers/FlyoutWindowPresenter.swift`
- `DI/managers/FlyoutFrameCalculator.swift`
- `DI/ContentView.swift`

## Lyrics: LRCLIB + NetEase providers, LRC parsing, synced highlight, side panel, inline line, pinned strip under the closed notch

### Behaviour

With 'Show lyrics' on, Atoll fetches timed lyrics for the playing track (not for ads or placeholder metadata). In the open notch either a scrolling side panel (title 'Lyrics' + pin button) with the current line highlighted by a word-by-word sweep (or a static gradient / solid colour), 'instrumental' rows shown as three music notes, auto-centred scrolling; or a single current-line marquee under the artist (standard player when the calendar is shown) / a two-line note-prefixed line (minimalistic). 'Keep lyrics under the closed notch' pins 1, 3 or 5 lines (10 pt) under the closed notch, hidden while a HUD is showing. Lines lead the voice by 0.25 s.

### Layout

Side panel (NotchHomeView.swift:239-321): VStack{ HStack(spacing 6){ 'Lyrics' .headline tinted ; Spacer ; pin 11 semibold 20×20 rotated 45° when unpinned }.padding(h12, top10, bottom6) ; SyncedLyricsList(style: sung .white, unsung tint.opacity(0.55), idle white 0.5, tint = avgColor.ensureMinimumBrightness(0.6) or .gray) }.background(black 0.3).clipShape(r4). SyncedLyricsStyle defaults (SyncedLyricsList.swift:121-143): fontSize 14, lineSpacing 8, lineLimit 2, instrumentalFontSize 12, horizontalPadding 12, verticalPadding 4, placeholder 'Show lyrics here'. Rows: LazyVStack in ScrollView, current row semibold, TimelineView 1/30 for the sweep, scroll to centre on index change (:145-245). Sweep (components/LockScreen/LyricSweep.swift:16-57): LinearGradient stops [sung@0, sung@p-0.06, unsung@p+0.06, unsung@1] leading→trailing, applied by hiding the text and masking the gradient with it; SweptLyricText (:91-225) splits words, weight = chars+1, WordFlowLayout spacing = measured space width, lineSpacing fontSize*0.28; per-word local progress. Gradient style: [tint, sung, tint 0.82] static. InstrumentalBreakNotes: three music.note (12 semibold) spacing 4 (:312-324). Pinned strip (PinnedLyricsView.swift): fontSize 10 medium, rowHeight = font line height +1, gap 4, padding.horizontal 10, rows = context (1/3/5), reserved height = rowHeight*context + 4, `.smooth(0.28)` on height, `.smooth(0.18)` on slots; sung .white, unsung tint 0.55, idle white 0.45; '♪' shown in gaps.

### Animations

Side panel scroll `.smooth(0.3)` (SyncedLyricsList.swift:242); lyric line swap in player `.easeInOut(0.32)` / `.smooth(0.32)` with move-up/down + opacity; sweep driven by 30 fps TimelineView (no implicit animation); pinned height `.smooth(0.28)`.

### State and timing

LyricsAvailability: loading/timed/untimed/instrumental/unavailable. 'Loading lyrics...' / 'No lyrics found' placeholders (MusicManager:1828,1993). Fetch on content change, duration-identity change, ad start/stop, and when the preference turns on.

### Data sources and APIs

Lookup key = normalised title/artist/album + (contentIdentifier or rounded duration) (MusicManager.swift:69-103); invalid when artist/title are placeholders (LyricsMetadata.swift:23-59). Title cleanup strips (feat./ft./featuring ...), trailing (remaster/live/mono/stereo) (MusicManager:1961-1980). Primary: `GET https://lrclib.net/api/search?track_name=&artist_name=` (diacritics folded) → filter rows agreeing on title AND artist (containment) and not carrying an unrequested version marker (karaoke, instrumental, sped up, slowed, nightcore, remix, re-record, 's version, cover, tribute, acapella, ...), prefer rows with syncedLyrics, then score title 8/4 + artist 8/4 + album 4/2 + synced 3 (LyricsMetadata.swift:75-253); instrumental flag trusted only on exact title and duration within 2 s. Fallback: NetEase `https://music.163.com/api/search/get/web?s=&type=1&limit=10` then `https://music.163.com/api/song/lyric?id=&lv=-1`, duration tolerance 2 s (NetEaseLyrics.swift:37-104). LRC parser handles multiple timestamps per line and `[offset:ms]` (managers/LRCParser.swift). Cache 80 entries, never caches 'unavailable' (MusicManager:659-693,1879-1881). Sync loop (:2049-2078): sleeps until the next timestamp, clamped 50-250 ms; position = estimate + 0.25 s lead (:2086-2115); instrumental break threshold 5 s (:2119). All public HTTPS.

### Settings

enableLyrics: Bool false (Constants.swift:1506); lyricHighlightStyle: .sweep|.gradient|.solid default .sweep (:1509); pinnedLyricContext: 1|3|5 default .current (:1511); pinLyricsWhenClosed: Bool false (:1512); lyricsPanelWidth: CGFloat 280 (:1513); lyricsPanelOffset: 0 (:1514); side panel only when enableLyrics && !showCalendar && !enableMinimalisticUI && showStandardMediaControls (sizing/matters.swift:45-51).

### Dependencies

None.

### Implementation notes

Port the provider logic as pure functions with unit tests (matching is the hard part); render sweep with the hidden-text + gradient-overlay + mask trick. ~900 lines.

### Key files

- `DI/managers/MusicManager.swift`
- `DI/managers/LyricsMetadata.swift`
- `DI/managers/NetEaseLyrics.swift`
- `DI/managers/LRCParser.swift`
- `DI/components/Music/SyncedLyricsList.swift`
- `DI/components/Music/PinnedLyricsView.swift`
- `DI/components/LockScreen/LyricSweep.swift`
- `DI/components/Notch/NotchHomeView.swift`

## Animated / live artwork (Apple Music editorial video, Spotify Canvas) and artwork-derived colours and glow

### Behaviour

With 'Show live canvas in Dynamic Island' the open-notch artwork plays the track's looping motion artwork (muted), paused when playback pauses. Independently, the album's dominant colour tints the artist line, slider, spectrum and glow; a radial blurred copy of the art glows behind it when playing.

### Layout

DynamicIslandArtworkSourceView (NotchHomeView.swift:196-221): video (AVPlayerLayer .resizeAspectFill) or Image, clipShape RoundedRectangle(cornerRadius, .continuous). Glow texture = `preBlurred(radius: 40)` (MusicManager.swift:1504).

### Animations

Player layer frame updates with CATransaction actions disabled to avoid double animation (:113-122); attach deferred one runloop turn.

### State and timing

Video URL fetched on every content change for Apple Music (cached by title|artist).

### Data sources and APIs

Apple Music: MusicKit (public, needs NSAppleMusicUsageDescription + user authorisation): `MusicCatalogSearchRequest(term: "title artist", types:[Song], limit 5)` then `MusicDataRequest` to `https://api.music.apple.com/v1/catalog/{storefront}/songs/{id}?extend=editorialVideo`, picks `motionTallVideo3x4` → `motionSquareVideo1x1` → first mvod m3u8 (AnimatedArtworkManager.swift:55-201); token-failure backoff 30→300 s. Only when bundle == com.apple.Music and `lockScreenMusicFullscreenVideoArtwork` (MusicManager:2209-2231). Spotify: canvas URL from spclient (see Spotify feature) via `liveArtworkURL`. Playback: `AVQueuePlayer` + `AVPlayerLooper`, muted, shared per URL registry, follows isPlaying (:29-95). Colours: `quickAverageColor()` downsamples to 32 px, averages RGB, lifts brightness to >= 0.5 (near-black → gray 0.5) (NSImage+Extensions.swift:138-204); `prominentOpposingColors` (vibrant mode) picks a dominant hue bucket and an opposing hue as secondary (:206-410); `ensureMinimumBrightness(factor)` scales RGB so luminance (0.2126/0.7152/0.0722) reaches the factor (:475-503); `getBrightness()` via CIAreaAverage (:414); `preBlurred(radius:)` CIGaussianBlur without clamp (:446-471). Computed only when coloredSpectrogram (MusicManager:1496-1499). REA: MusicKit symbols imported (macho.json), NSAppleMusicUsageDescription present.

### Settings

showLiveCanvasInDynamicIsland: Bool false (Constants.swift:1515); lockScreenMusicFullscreenVideoArtwork: Bool true (:1147); coloredSpectrogram true; colorExtractionMode .vibrant; lightingEffect true.

### Dependencies

None (MusicKit, CoreImage, AVFoundation).

### Implementation notes

Public path exists for Apple Music; skip Spotify canvas. Colour helpers are ~200 lines of CoreImage/CG code. ~400 lines total.

### Key files

- `DI/managers/AnimatedArtworkManager.swift`
- `DI/components/Notch/NotchHomeView.swift`
- `DI/extensions/NSImage+Extensions.swift`
- `DI/managers/MusicManager.swift`

## Marquee text and explicit badge (MarqueeText, MusicTitleMarqueeView, MusicExplicitBadge)

### Behaviour

Titles/artists wider than their slot scroll left continuously (two copies, 20 pt gap) after a pause, snap back and repeat; short text does not scroll. Explicit tracks show a rounded 'E' chip after the title.

### Layout

MarqueeTextView.swift:40-157: ZStack{ HStack(spacing loopSpacing 20){ Text; Text(opacity needsScrolling ? 1 : 0) }.fixedSize(h).offset(x) }.frame(width: frameWidth, .leading).clipped().frame(height: pointSize*1.3). MusicExplicitBadge (:159-183): Text 'E' .system(fontSize 9 default, .bold, .rounded) white 0.92 on white 0.18 RoundedRectangle r = max(4, height*0.28) continuous, height 14 default, padding.horizontal max(4, h*0.2). MusicTitleMarqueeView (:185-311): HStack(spacing 6){ marquee-or-Text ; badge } with badge height default max(12, pointSize*1.12), font height*0.6, reserved width = h + 0.7h + 6.

### Animations

Initial 0.1 s settle; wait `minDuration` (default 3 s; 0.4 s in closed inline peek, 1 s in standard peek, 0.35 s for lyrics); then `.linear(duration: textWidth/30)` (30 pt/s) to -(textWidth+20); snap back with `.none`; loop (:114-156).

### State and timing

Restarts on text change.

### Data sources and APIs

Pure SwiftUI; measures via NSFont.preferredFont(forTextStyle:).

### Settings

None.

### Dependencies

None.

### Implementation notes

~150 lines; consider TimelineView-based implementation for Swift 6 safety.

### Key files

- `DI/components/Live activities/MarqueeTextView.swift`

## Unknowns

- Lock-screen music panel (components/LockScreen/LockScreenMusicPanel.swift, FullScreenArtworkWindowManager, LockScreenManager) and its glass styles — large, belongs to the lock-screen subsystem; shares MusicSliderView/VolumeCapsuleSlider (VolumeCapsuleSlider.swift: track 13/10 pt, fill opacity 0.55/0.8/1, swell y1.14 .spring(0.3,0.75)).
- Exact internals of MediaRemoteAdapter.framework (compiled BSD-3 binary from github.com/ungive/mediaremote-adapter); only exported symbol names and the perl CLI contract were inspected. Whether NotchIsland may redistribute it is a licensing (BSD-3 attribution) and App-Store-policy question, not a technical one.
- SkyLightWindow package (Lakr233) — used for the floating control window; private CGS/SkyLight APIs; license not checked.
- Spotify artist-name canonicalisation (`SpotifyTrackMetadataResolver`, SpotifyController.swift ~390-600) and the protobuf canvas request encoder — not read in detail.
- YouTube Music WebSocket message handling (`YouTubeMusicWebSocketClient`, Controller:215-318) and like-button state parsing — only endpoints and intervals captured.
- TIDAL Accessibility menu traversal details (menu titles, timeouts) in TidalController.swift:162-410 — captured API surface only.
- Per-app volume (audio/PerAppVolume, PerAppVolumeManager) and MediaKeyInterceptor (hardware media keys) — separate HUD/volume subsystem.
- Extension (AtollExtensionKit) payload pairing in the music right wing (ExtensionMusicWingView, ExtensionLayoutMetrics) — third-party extension subsystem.
- Dynamic Island (non-notch pill) mode specifics for the closed music activity (dynamicIslandPillCornerRadiusInsets 24 / 16, top offset 6, shadow inset 14) — core notch subsystem.
- HoverButton remaining press-effect code paths (HoverButton.swift:119-164) partially read; constants captured.
- Whether metal/visualizer.metal is referenced anywhere at runtime (no Swift call site found in the music views; default.metallib exists in the bundle, MTKView symbols in dispatch.json likely belong to SwiftTerm's Metal renderer).
- Spotify like/favourite web API endpoints (SpotifyFavoriting, SpotifyController.swift:840-903) — require the sp_dc-derived token; not read line by line.
- Exact `parallax3D` offset normalisation (View+Parallax3D.swift:34-50) and the `isSuspended` condition.
- Timer/reminder/recording/focus/caps-lock right-wing supplement views (MusicTimerSupplementView etc., ContentView.swift:3033+) — other subsystems; width formulas captured.

## Critic pass

Missing from the spec:

- TRUNCATION NOTE: the spec text handed to me ends mid-sentence inside feature 6 (MusicControlOverlay, '...notchWidth = closedNotchWidth + (ho'). Features 7-9 (lyrics, animated artwork, flip) exist only as summary bullets, so every lyrics/overlay/animated-artwork item below is 'missing unless it is in the truncated tail'. Verified-present items from the visible part are not repeated here.
- MinimalisticMusicView is dead code: `grep -rn 'MinimalisticMusicView('` over DynamicIsland/ finds no call site (only the struct at components/MinimalisticMusicView.swift:25). The closed notch in Minimalistic mode uses the same MusicLiveActivity (ContentView.swift:1393); the spec should not present this file as the shipping 'minimalistic closed variant'.
- Settings keys never mentioned: musicAuxLeftControl/musicAuxRightControl (MusicAuxiliaryControl .shuffle/.repeatMode/.mediaOutput/.lyrics, defaults .shuffle/.repeatMode) + didMigrateMusicAuxControls + didMigrateMusicControlSlots (legacy -> musicControlSlots migration) — models/Constants.swift:1081-1085, enum :595-640.
- Settings keys never mentioned: enableFullscreenMediaDetection (Bool true, Constants.swift:1068) and hideNotchOption (HideNotchOption .always/.nowPlayingOnly/.never, default .nowPlayingOnly, Constants.swift:1237, enum :395-399). Feature: observers/FullscreenMediaDetection.swift hides the closed notch when the now-playing app's bundle (musicManager.bundleIdentifier) is in NATIVE fullscreen on that screen; uses MacroVisionKit (third-party, public) window scan + AX attribute 'AXFullScreen' via AXUIElementCreateApplication/kAXFocusedWindowAttribute/kAXWindowsAttribute (:120-146, requires Accessibility, falls back to frame-based when untrusted); 500 ms debounce after NSWorkspace.activeSpaceDidChange / didChangeScreenParameters (:70-73); Finder excluded; SettingsView.swift:3624-3634 sets enableFullscreenMediaDetection = hideNotchOption != .never.
- Settings key never mentioned: lyricHighlightStyle (LyricHighlightStyle .sweep/.gradient/.solid, default .sweep; Constants.swift:1509, enum :423-437). Rendering in components/LockScreen/LyricSweep.swift (SweptLyricText.body :152-158): sweep = per-word WordFlowLayout; gradient = one fixed LinearGradient [tint, sung(white), tint 0.82] leading->trailing; solid = flat sung colour. Settings picker 'Highlight' + explanation at SettingsView.swift:3382-3400.
- Settings keys only implied: pinnedLyricContext (PinnedLyricContext Int 1/3/5, default .current=1; Constants.swift:1511, enum :408-421) and pinLyricsWhenClosed (Bool false; :1512). Spec summary says '1/3/5-line strip' but never names the keys or the pin button (NotchHomeView.swift:273-299: pin.fill/pin 11 pt semibold in a 20x20 frame, rotated 45 deg when unpinned, toggled inside withAnimation(.smooth); SettingsView.swift:3403-3418 toggle 'Keep lyrics under the closed notch' + 'Pinned lyric context' picker).
- Pinned lyrics strip details (components/Music/PinnedLyricsView.swift): font 10 pt .medium, rowHeight = (ascender-descender+leading).rounded(.up)+1, gap 4, horizontal padding 10, strip height = rowHeight*context + gap, implemented as .padding(.bottom, height) + overlay so it never changes the notch width (:27-49); height animates .smooth(0.28), slot text .smooth(0.18); TimelineView 1/30 s paused when !isPlaying; words hidden (opacity 0) while a sneak peek or connectivity HUD is visible (ContentView.swift:1275-1276); reserved only when enableLyrics && pinLyricsWhenClosed && notch closed && !hideOnClosed && !locked && isPlaying && lyricsAvailability == .timed (ContentView.swift:2450-2458, PinnedLyricsView.swift:91-99); also added to the closed window height (ContentView.swift:2419-2420). Colours: sung .white, unsung tint.opacity(0.55) where tint = playerColorTinting ? avgColor.ensureMinimumBrightness(0.6) : .gray, idle .white 0.45; '♪' shown for the current slot during an instrumental gap (SyncedLyricsList.swift PinnedLyricsContextRows :~130).
- Side-panel lyrics list (components/Music/SyncedLyricsList.swift): SyncedLyricsStyle defaults fontSize 14, currentFontSize nil, lineSpacing 8, lineLimit 2, instrumentalFontSize 12, horizontalPadding 12, verticalPadding 4, placeholder 'Show lyrics here'; LazyVStack in ScrollView(.vertical) with scrollIndicators(.never); redraw in TimelineView 1/30 s; scrollTo(current, anchor: .center) with .smooth(0.3) on index change and non-animated on appear/new lyrics; instrumental marker rows (InstrumentalBreakNotes = 3x 'music.note' spacing 4) inserted for blank LRC timestamps or intros whose gap >= MusicManager.instrumentalBreakThreshold = 5 s (MusicManager.swift:2119). Panel style passed from LyricsSidePanelView (NotchHomeView.swift:252-259): sung .white, unsung artistLineColor.opacity(0.55), idle .white 0.5, tint artistLineColor.
- Lyric sweep internals (components/LockScreen/LyricSweep.swift — note it lives under LockScreen but is used by the notch): feather 0.06 (:~22); current line drawn as hidden content + gradient overlay masked by the content (:46-56); per-word progress slices weighted by (characterCount+1) (:132-146); WordFlowLayout lineSpacing = fontSize*0.28, spacing = measured NSFont space width; layout cache capped at 400 entries (:118-128).
- Lyrics acquisition details missing: LRCLIB URL is https://lrclib.net/api/search?track_name=…&artist_name=… with diacritic-folded, percent-encoded title/artist (MusicManager.swift:1903-1913); request title normalisation strips remaster/live/mono/stereo markers (normalizedLyricsTitle :1961-1979); lyrics cache limit 80 entries keyed by LyricsLookupKey incl. duration (MusicManager.swift:661-662, :69-105); LyricsProviderFallback runs LRCLIB then NetEase only when availability == .unavailable (LyricsMetadata.swift:~290-315); LyricsAvailability enum .loading/.timed/.untimed/.instrumental/.unavailable; filter-then-rank matching: title & artist must overlap, version markers (karaoke, instrumental, sped up, slowed, nightcore, remix, re-record, "'s version", cover, tribute, acapella, a cappella, made popular by, originally performed by) reject rows, rows with syncedLyrics always beat rows without, then score title 8/4, artist 8/4, album 4/2, +3 synced (LyricsMetadata.swift:~75-240); instrumental flag trusted only for exact title and |duration diff| <= 2 s; placeholder metadata ('Track 7' / 'Unknown artist' patterns) skips lookup entirely (LyricsMetadata.swift:~25-70); LyricTextSemantics drops credit lines (作词/作曲/lyrics by/composer/…) and placeholder bodies (纯音乐请欣赏/instrumental/nolyrics) from display.
- NetEase provider (managers/NetEaseLyrics.swift): search https://music.163.com/api/search/get/web?s={title artist}&type=1&limit=10 (artist '/' replaced by space; '&+=/?#' escaped), lyric https://music.163.com/api/song/lyric?id={id}&lv=-1; durationTolerance 2 s; nolyric -> instrumental, uncollected -> none; duration (ms) /1000; same filter-then-rank scoring (8/4) with duration-distance tiebreak.
- LRC parser (managers/LRCParser.swift): time tag regex \[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\] with fraction scaled by digit count, multiple tags per line emit the line at each timestamp, [offset:±ms] tag shifts all lines (positive = earlier), bare timestamps kept as empty lines (break markers), output sorted by timestamp.
- Lyric sync loop (MusicManager.swift:2050-2200): startLyricSync only when hasTimedLyrics; loop sleeps delayUntilNextLyric = clamp((nextTimestamp - position)/playbackRate, 0.05, 0.25) (:2191-2200); lyricLeadTime 0.25 s added to every position (:2115); lyricPlaybackPosition uses max(estimatedPosition, elapsed) or raw extrapolation when duration is 0 (:2080-2100); currentLyricIndex -1 before first line; isInInstrumentalBreak / lyricWindow / currentLyricSweepProgress (:2120-2180) drive the InstrumentalBreakNotes in the standard player (NotchHomeView.swift:513-524) and the sweep.
- Animated artwork specifics (managers/AnimatedArtworkManager.swift): MusicAuthorization.request(); MusicCatalogSearchRequest(term: "title artist", types: [Song]) limit 5, match exact title+artist -> exact title -> first (:106-128); storefront from MusicDataRequest.currentCountryCode else "us"; GET https://api.music.apple.com/v1/catalog/{storefront}/songs/{id}?extend=editorialVideo via MusicDataRequest; prefers editorialVideo.motionTallVideo3x4.video, then motionSquareVideo1x1.video, then regex https://mvod\.itunes\.apple\.com…\.m3u8 (:143-190); per-song cache keyed "title|artist"; developer-token failure backoff 30->60->120->240->300 s cap (:36-52, :196-228). Gate: MusicManager.fetchVideoArtwork() runs only when Defaults[.lockScreenMusicFullscreenVideoArtwork] (Constants.swift:1147, default true) AND bundleIdentifier == com.apple.Music (MusicManager.swift:2216-2232); Spotify instead supplies PlaybackState.liveArtworkURL (Canvas).
- Canvas/video playback plumbing (NotchHomeView.swift:30-220): DynamicIslandArtworkLoopRegistry shares one AVQueuePlayer+AVPlayerLooper per URL with manual refcount; player.isMuted = true, actionAtItemEnd = .none; play/pause follows MusicManager.$isPlaying; AVPlayerLayer videoGravity .resizeAspectFill with CATransaction.setDisableActions in layout(); DynamicIslandArtworkSourceView(cornerRadius:contentMode:prefersVideo:) swaps video for the still when showLiveCanvasInDynamicIsland && videoArtworkURL != nil (minimalistic glow uses prefersVideo: false).
- Spotify canonical artist name resolution (SpotifyController.swift:383-520 'trackMetadataResolver'): GET https://api.spotify.com/v1/tracks/{id} with the web-player token from SpotifyAuthManager, falling back to the public embed page; cache 1 h hit / 5 min miss; artist replaced in PlaybackState asynchronously (:280-300). Spec mentions 'canonical artist names' with no mechanism.
- Spotify like button = separate OAuth 2.0 PKCE flow (managers/Spotify/*): SpotifyOAuthService scopes 'user-library-read user-library-modify', redirect atoll-spotify://oauth-callback, https://accounts.spotify.com/authorize + /api/token, expiryLeeway 60 s; ASWebAuthenticationSession (SpotifyAuthSession.swift); tokens in Keychain (KeychainSpotifyTokenStore) with one-time migration from Defaults spotifyLibraryAccessToken/RefreshToken/TokenExpiration (Constants.swift:1264-1268); SpotifyLibraryAPI base https://api.spotify.com/v1, Retry-After capped 5 s default 1 s; user-supplied spotifyLibraryClientID (Constants.swift:1248). Settings UI: SpotifyAuthSettingsSection, SpotifyLikeButtonSettingsSection, SpotifyLoginSheet (shown only when mediaController == .spotify, SettingsView.swift:3251-3254).
- Favouriting back-ends not detailed: Cider GET http://localhost:10767/api/v1/playback/now-playing -> info.inFavorites, POST …/set-rating {rating: 1|0}, header 'apptoken' (CiderController.swift:58-160), token in Keychain service com.Ebullioscopic.Atoll.Cider / account appToken (CiderTokenStore.swift:25-26), only while Cider is running; YouTube Music GET /api/v1/like-state (LIKE/DISLIKE/INDIFFERENT) and POST /api/v1/like presses the button only if state differs (YouTubeMusicController.swift:509-590); TIDAL favourite read via AX kAXDescriptionAttribute labels 'Add to My Collection' / 'Remove from My Collection' on a cached player-bar button, write unsupported (TidalController.swift:157-230); MediaControllerProtocol has canEverFavorite / supportsFavoriting / favoritingIsReadOnly (MediaControllerProtocol.swift:41-66); LikeTrackPresentation dims to 0.4 while unknown and disables when read-only (components/Notch/LikeTrackControl.swift).
- Settings UI components not in spec: MediaSourceCapabilitiesButton/Table (components/Settings/MediaSourceCapabilities.swift: ⓘ popover 420 pt wide, padding 16, columns 120/74, per-source Favorite/Shuffle/Repeat matrix with TIDAL favourite read-only and Amazon none); MusicSlotConfigurationView (components/Settings/MusicSlotConfigurationView.swift: drag/drop 5-slot editor, slot tiles 56x56 r10, palette tiles 48x48 r10 and 44x44 r8, icon 15 pt / 18 pt for playPause, 72 pt 'Clear slot' drop target); onboarding MusicControllerSelectionView (components/Onboarding/MusicControllerSelectionView.swift) which hides .nowPlaying when deprecated (:32-37); CiderFavoritingSettingsSection; Appearance-tab toggles cornerRadiusScaling/coloredSpectrogram/playerColorTinting/lightingEffect + 'Slider color' picker (SettingsView.swift:4933-4985); custom Lottie visualizer manager (add by name/URL/speed, list, select, delete; SettingsView.swift:4866-5152); Gestures tab enableHorizontalMusicGestures + musicGestureBehavior (SettingsView.swift:1353-1366); media-tab labels 'Enable customizable controls' (Beta), 'Show "Change Media Output" control', 'Skip buttons' segmented picker, 'Show live canvas in Dynamic Island', 'Parallax Effect Intensity' slider 0...12 step 1, 'Show song title and artist on non-notch displays', 'Enable real-time waveform' (Beta), 'Visualizer candles' 4/5/6, 'Color extraction' Legacy/Vibrant, 'Scrubbable real-time waveform', footer 'Requires macOS 14.2+' (SettingsView.swift:3290-3345, 3462-3540).
- Colour extraction algorithm (extensions/NSImage+Extensions.swift:206-410) is unspecified: downsample to 64x64; vibrant mode ignores pixels with brightness < 0.10 or > 0.95 or saturation < 0.20, weight = saturation^2 * brightness, 16 hue buckets, primary = heaviest bucket with saturation x1.20 and brightness x1.10 (clamped to 1), secondary = heaviest bucket >= 60 deg of hue away with the same boost, fallback complementary hue+0.5; legacy mode = mean RGB with min brightness 0.5 (near-black -> gray 0.5; saturation scaled by brightness/0.5), secondary = hue+180 deg. quickAverageColor() (:138-204) is a synchronous 32-px pass applied first, then prominentOpposingColors async (MusicManager.swift:1493-1497) — and only when coloredSpectrogram is on. ensureMinimumBrightness(factor:) scales RGB by factor/(0.2126R+0.7152G+0.0722B) (:475-504); getBrightness() via CIAreaAverage (:414-442); preBlurred(radius:) = CIGaussianBlur without clampedToExtent (:444-472); spectrogramGradient(secondary:) top->bottom [self, secondary ?? hue+180] or self.gradient in legacy mode (:507-538).
- MarqueeText internals (components/Live activities/MarqueeTextView.swift): two copies with loopSpacing 20 pt, scroll speed ≈30 pt/s (duration = width/30), 0.1 s settle then minDuration pause, .linear move by -(width+20), instant snap back, loop; frame height = NSFont pointSize * 1.3; width recovered as (loopWidth-20)/2 (:40-75). MusicExplicitBadge defaults: 'E' 9 pt bold rounded, height 14, horizontal padding max(4, 0.2h), bg white 0.18, fg white 0.92, corner max(4, 0.28h). MusicTitleMarqueeView reserves badge width h + 0.7h + 6 and defaults badgeHeight to max(12, pointSize*1.12); scrolling decided by NSFont measurement.
- Floating control window plumbing (likely in truncated tail — verify): musicControlPauseGrace = 5 s (ContentView.swift:306, used :2734-2738); shouldShowMusicControlWindow requires musicControlWindowEnabled && coordinator.musicLiveActivityEnabled && standardMediaControlsActive (showStandardMediaControls && !enableMinimalisticUI) && closed && !hideOnClosed && !locked && !deferredAfterUnlock && !suppressed && (isPlaying || within grace) (ContentView.swift:2845-2858); metrics spacing 36 (ContentView.swift:2938-2941); MusicControlWindowManager initial window 240x68 (managers/MusicControlWindowManager.swift:41); FlyoutWindowPresenter: NSPanel at CGShieldingWindowLevel(), collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary], SkyLightOperator.shared.delegateWindow (PRIVATE SkyLight), NSAnimationContext durations 0.24 present / 0.16 refresh / 0.18 hide (managers/FlyoutWindowPresenter.swift:75,143,191,203,257-274); FlyoutFrameCalculator originX = screen.midX + notchWidth*0.5 + rightWingWidth + spacing, originY = screen.maxY - height (managers/FlyoutFrameCalculator.swift:30-52); overlay .animation(.smooth(0.2)) on isPlaying/skipBehavior/controlsEnabled and play/pause corner max(buttonCornerRadius+2, playPauseSide*0.32) (MusicControlOverlay.swift:128-160); when showStandardMediaControls turns off the window pref is cached & disabled (DynamicIslandApp.swift:1798-1813).
- Right-wing supplement views when music is paired with a secondary activity: MusicTimerSupplementView (ContentView.swift:3033-3149), MusicReminderSupplementView (:3150-3230), MusicCapsLockLabelView ('Caps Lock' 13 pt semibold trailing, :3231-3242), ExtensionMusicWingView (components/Extensions/ExtensionLiveActivityViews.swift:85). Metrics (ContentView.swift:3250-3296): timer countdown 13 pt semibold monospaced, frame max(textWidth+16, 72); timer name 12 pt medium, max(width+14, 64); reminder digital 'mm:ss' 15 pt semibold monospaced-digit, max(width+18, 76); reminder minutes 'in N min' 13 pt semibold, max(width+18, 88); reminder ring diameter max(min(notchHeight-12, 22), 16); timer ring 30 pt wide with 8 pt spacing; progress bars 3 pt tall. Extension wing max width = baseWidth + centerBaseWidth*0.6 (ContentView.swift:1572-1574). Spec only lists approximate width factors.
- Inline (expanding) sneak peek also handles the TIMER type inside MusicLiveActivity: inlineSneakPeekActive includes expandingView.type == .timer (ContentView.swift:1405-1410) and the centre overlay shows timer name marquee (minDuration 0.4) + formattedRemainingTime in timerColor (:1468-1483). showSongMetadataInClosedNotch marquee uses minDuration 3, frameWidth effectiveCenterWidth-16, padding.horizontal 8 and only on non-notch screens (:1485-1493; isNonNotchScreen :427-432).
- Open-notch height grows by inlineLyricsLineHeight = 18 pt whenever inline lyrics are enabled on the Home tab (standard player, calendar on, player visible) — sizing/matters.swift:252-285, applied in DynamicIslandApp.swift:582 and DynamicIslandViewModel.swift:431. Side-lyrics width recomputation subscribes to enableLyrics/lyricsPanelWidth/lyricsPanelOffset/isPlaying/songTitle/artistName (DynamicIslandViewModel.swift:294-313). The closed window size uses the same pairing predicate (DynamicIslandApp.swift:617-633).
- MusicSliderView fallback when duration is unusable (NotchHomeView.swift:1177-1215): non-interactive track with surrogate duration max(1, estimated*2, elapsed*2), gray 0.3 track + tint fill, no seeking, labels '--:--'. Also CustomSlider.desaturatesWhenIdle / trackOpacity 0.82 (lock-screen only), MusicSliderView.tintOverride, and the standard app-icon badge is hidden when usingAppIconForArtwork (NotchHomeView.swift:423-432).
- Parallax modifier also applies .scaleEffect(isHovering ? 1.02 : 1.0) and skips hover math while a mouse button is pressed (extensions/View+Parallax3D.swift:~45-80). HoverButton nudge returns after 0.16 s, wiggle angle ±10 deg (components/HoverButton.swift:~110-135). Minimalistic MinimalisticMediaOutputButton / MinimalisticAirPlayButton (MinimalisticMusicPlayerView.swift:1100-1220) reuse the same popovers.
- Closed-notch hover play/pause overlay only appears when there is NO secondary activity (shouldShowClosedMusicWaveformPlayPauseOverlay guards secondary == nil, ContentView.swift:2099-2102); isClosedMusicGestureContext additionally requires !isCurrentScreenExpansionVisible and !coordinator.firstLaunch (:2104-2113).
- Media-source helpers not described: AppleScriptHelper runs NSAppleScript inside Task.detached(priority: .userInitiated) (helpers/AppleScriptHelper.swift:27-40) plus a synchronous AppleScriptRunner; ImageService uses a dedicated URLSession with a 50 MB memory URLCache and 'artwork_cache' disk directory (managers/ImageService.swift:36-49); MediaChecker has a 10 s timeout and treats non-zero exit WITH stderr as script failure rather than deprecation (helpers/MediaChecker.swift:57-105); NowPlayingTestClient helper binary ships at Contents/Helpers/NowPlayingTestClient (graph.json) and is required for the probe (MediaChecker.swift:43-51); JSONLinesPipeHandler actor (NowPlayingController.swift:557+) line-buffers the adapter stdout; perl script exposes stream/test subcommands and --micros (mediaremote-adapter/mediaremote-adapter.pl).
- Per-app volume mixer is an adjacent feature built on the same process-tap stack and is absent: audio/PerAppVolume/AppVolumeTap.swift, AudioProcessQuery.swift (kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioProcessPropertyBundleID/PID/IsRunningOutput — all public), managers/PerAppVolumeManager.swift, components/Audio/PerAppVolumePopover.swift, Defaults perAppVolumeLevels/perAppVolumeMuted (Constants.swift:1343-1344). VolumeCapsuleSlider (components/Music/VolumeCapsuleSlider.swift: track 13/10 pt, glyph 11.5/10 pt, fill opacity 0.55/0.8/1.0, y-scale 1.14 while dragging, springs 0.28/0.8 & 0.32/0.8 & 0.3/0.75, accessibility step 1/16) sits in components/Music but is never mentioned.
- Lock-screen music surfaces consume the same MusicManager and should be cross-referenced: components/LockScreen/LockScreenMusicPanel.swift (collapsedHeight 180, defaultCollapsedWidth 390, expandedSize 720x340, :31-41), managers/FullScreenArtworkWindowManager.swift (AVQueuePlayer/AVPlayerLooper fullscreen canvas behind the lock screen, SpotifyCanvasFallbackArtworkOverlayView per dispatch.json, SkyLight), Defaults lockScreenMusic* keys (Constants.swift:1110-1147), enableLockScreenMediaWidget + cachedLockScreenMediaWidgetPreference (:1091-1094), alwaysShowLockScreenVolume (:1080), lockScreenShowAppIcon.
- Behavioural test oracles exist and are not referenced: DynamicIslandTests/AppleMusicControllerTests.swift, AudioTapTests.swift, CiderFavoritingTests.swift, LyricsMetadataTests.swift, MarqueeTextMeasurementTests.swift, NetEaseLyricsTests.swift, NowPlayingPayloadTests.swift, PinnedLyricsTests.swift, SpotifyLibraryTests.swift, UnsyncedLyricsTests.swift.
- Minor: AppIcon(for:) badge can be overridden by user customAppIcons (Constants.swift:50, helpers/AppIcons.swift); BluetoothAudioManager AirPods listening-mode sneak peek (.bluetoothAudio) can pre-empt the music live activity row (ContentView.swift:1099-1101, 1131); MediaKeyInterceptor (managers/MediaKeyInterceptor.swift) is NOT a playback feature — it taps volume/brightness keys via CGEvent.tapCreate (HUD subsystem) and should not be confused with media transport.

Corrections:

- WRONG (feature 5 'Horizontal music gestures'): 'during the drag the closed notch wings widen by gestureProgress = translation/sensitivity*20 (:2600,2628)'. Those lines are inside handleOpenScrollGesture / handleCloseScrollGesture — the VERTICAL swipe-to-open/close gesture (ContentView.swift:2596-2645). handleSkipGesture (:2650-2676) never touches gestureProgress; a horizontal swipe does not widen the wings. The wings widen (wingBaseWidth += gestureProgress/2, :1398) only during a vertical open gesture on the closed notch.
- WRONG (feature 'Closed-notch Music Live Activity', key_files/layout): components/MinimalisticMusicView.swift:24-126 is presented as the 'Minimalistic closed variant'. The struct has no call sites anywhere under DynamicIsland/ (grep 'MinimalisticMusicView(' returns only the definition at :25); the closed notch in Minimalistic mode renders the same MusicLiveActivity (ContentView.swift:1393-1518). Treat the file as dead code.
- WRONG citation (Now Playing settings): 'ciderApiToken (Constants.swift:1250)'. Line 1250 is a comment; the key is `legacyCiderAPIToken` with stored name "ciderAPIToken" at models/Constants.swift:1263 and is migration-only. The live Cider token is read from the Keychain by CiderTokenStore (service com.Ebullioscopic.Atoll.Cider, account appToken; MediaControllers/CiderTokenStore.swift:25-26).
- WRONG/INCOMPLETE (closed-notch right wing widths): 'timer: max(base, centerBase*0.38..0.52, base+12..24)' only holds when the timer countdown is hidden. When timerShowsCountdown the wing is max(baseWidth, 18 + (ring ? 30 : 0) + (ring ? 8 : 0) + max(countdownTextWidth+16, 72)) (ContentView.swift:1587-1595, 3258-3260). The spec also omits the reminder wing: max(baseWidth, 16 + ringDiameter) for ring style, or 16 + max(textWidth+18, 76 | 88) for digital/minutes (:1597-1612, 3269-3296).
- UNVERIFIED claim (closed-notch spectrum): 'clicking toggles playback with a haptic'. No call to togglePlay()/playPause() exists in ContentView.swift (grep over the file finds none); the hover overlay (ContentView.swift:1779-1799) is allowsHitTesting(false). Either cite the actual tap handler (possibly in the window/tap gesture layer) or drop the claim.
- WRONG (animated artwork, summary bullet 8): Apple Music editorial video fetching is NOT gated by showLiveCanvasInDynamicIsland. MusicManager.fetchVideoArtwork() returns early unless Defaults[.lockScreenMusicFullscreenVideoArtwork] (Constants.swift:1147, default true) and bundleIdentifier == "com.apple.Music" (MusicManager.swift:2216-2232). showLiveCanvasInDynamicIsland (Constants.swift:1515) only controls whether the notch artwork tile displays videoArtworkURL (NotchHomeView.swift:204-205, 329-331).
- DOUBTFUL rationale (REA summary): 'cs.disable-library-validation (needed for perl to dlopen the adapter framework)'. The entitlement is on the Atoll executable (signature.json); the adapter framework is loaded by a separate /usr/bin/perl child via DynaLoader (mediaremote-adapter.pl:9), which Atoll's entitlements do not govern. Report the entitlement as present without that justification.
- EVIDENCE MISMATCH (REA summary): 'graph.json lists Contents/Resources/MediaRemoteAdapter.framework/... and the Resources dir holds mediaremote-adapter.pl and default.metallib'. graph.json (as parsed) lists MediaRemoteAdapter.framework and Contents/Helpers/NowPlayingTestClient but contains no entry for mediaremote-adapter.pl or default.metallib; cite the filesystem listing of /Applications/Atoll.app for those two files, or drop the metallib claim.
- INCOMPLETE (REA summary, entitlements): temporary-exception.apple-events lists com.spotify.client, com.apple.Music AND com.apple.Notes (signature.json); NSAppleEventsUsageDescription reads 'Atoll uses AppleScripts to control Spotify, Apple Music, and Notes.' (plist.json).
- MINOR citation (feature 1 'animations'): AlbumArtFlipModifier is at MusicManager.swift:2305-2340 (struct 2305-2334, View extension 2336-2340), not 2309-2341; the separate file extensions/AlbumArtFlipModifier.swift is an 18-line licence-only stub with no code.
- MINOR (feature 'Audio visualizer', data_sources): the 'PUBLIC CoreAudio process-tap API' list should also name kAudioHardwarePropertyTranslatePIDToProcessObject and kAudioProcessPropertyPID/IsRunningOutput (audio/PerAppVolume/AudioProcessQuery.swift:34,65,88,106; TidalController.swift:55-68 relies on isRunningOutput), and note macho.json imports confirm _AudioHardwareCreateProcessTap/_AudioHardwareDestroyProcessTap/_AudioHardwareCreateAggregateDevice/_AudioHardwareDestroyAggregateDevice/_AudioDeviceCreateIOProcID (all public CoreAudio).
- MINOR (public reimplementation path): 'use MusicKit (public) for animated artwork' needs the caveat that MusicCatalogSearchRequest/MusicDataRequest require an App ID with the MusicKit capability so an automatic developer token is issued; Atoll's AnimatedArtworkManager has an explicit 30-300 s back-off for 'Client not found'/-8200 developer-token failures (AnimatedArtworkManager.swift:36-52, 196-228). NSAppleMusicUsageDescription in the shipped plist is 'Atoll uses Apple Music to fetch animated artwork for the lock screen wallpaper.'

Private API summary:

PRIVATE macOS APIs in the music subsystem (source + REA macho.json): (1) MediaRemote.framework — /System/Library/PrivateFrameworks/MediaRemote.framework is NOT in macho.json's 75 link-time dependencies; it is loaded at runtime with CFBundleCreate + CFBundleGetFunctionPointerForName (both present in macho.json imports) in NowPlayingController.swift:66-93 and the FilteredNowPlayingController base used by Amazon/TIDAL/Cider (AmazonMusicController.swift:63-90) for MRMediaRemoteSendCommand (0 play/1 pause/2 toggle/4 next/5 prev), MRMediaRemoteSetElapsedTime, MRMediaRemoteSetShuffleMode (1 off/3 on), MRMediaRemoteSetRepeatMode (1/2/3); dispatch.json confirms the Swift stored properties MRMediaRemoteSendCommandFunction/SetElapsedTimeFunction/SetShuffleModeFunction/SetRepeatModeFunction plus NowPlayingController, FilteredNowPlayingController, MediaChecker and isNowPlayingDeprecated shipped in 2.3.3. Now-playing METADATA for those four sources comes from the bundled BSD-3 ungive/mediaremote-adapter: Contents/Resources/MediaRemoteAdapter.framework (graph.json) loaded by a /usr/bin/perl child running mediaremote-adapter.pl stream [--micros] (NowPlayingController.swift:258-307), which internally calls MRMediaRemoteRegisterForNowPlayingNotifications/GetNowPlayingInfo etc.; a deprecation probe runs the adapter's test command against Contents/Helpers/NowPlayingTestClient (graph.json; helpers/MediaChecker.swift) and falls back to Apple Music when MediaRemote is unusable. Apple Music, Spotify and YouTube Music sources use NO private API (NSAppleScript + DistributedNotificationCenter + apple-events entitlement with temporary exceptions for com.spotify.client/com.apple.Music/com.apple.Notes; th-ch local HTTP/WebSocket on localhost:26538). (2) SkyLight / CoreGraphics window-server private calls — the Lakr233/SkyLightWindow SwiftPM package (SkyLightOperator.shared.delegateWindow) is used by FlyoutWindowPresenter for the floating MusicControlOverlay window (managers/FlyoutWindowPresenter.swift:75) and by FullScreenArtworkWindowManager / lock-screen panels; private/CGSSpace.swift declares @_silgen_name _CGSDefaultConnection, CGSSpaceCreate/Destroy/SetAbsoluteLevel, CGSShowSpaces/HideSpaces, CGSAddWindowsToSpaces/RemoveWindowsFromSpaces for the notch's own space (core subsystem). macho.json imports confirm __CGSDefaultConnection, _CGSSpaceCreate, _CGSSpaceDestroy, _CGSSpaceSetAbsoluteLevel, _CGSShowSpaces, _CGSHideSpaces, _CGSAddWindowsToSpaces, _CGSRemoveWindowsFromSpaces, _CGSRegisterNotifyProc, _CGSIsScreenWatcherPresent. Public alternative: an NSPanel at CGShieldingWindowLevel() (public, also imported) with [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary] — which the presenter already sets — loses only lock-screen/above-fullscreen placement. (3) Undocumented-but-public-API usage requiring Accessibility permission: the AX attribute "AXFullScreen" read through AXUIElementCopyAttributeValue for fullscreen media detection (observers/FullscreenMediaDetection.swift:120-146), and TIDAL shuffle/repeat/favourite via AXUIElementCreateApplication + menu-bar Playback menu items + kAXPressAction (TidalController.swift:157-410); macho.json confirms _AXUIElementCreateApplication, _AXUIElementCopyAttributeValue, _AXUIElementCreateSystemWide, _AXIsProcessTrusted(WithOptions). (4) Non-Apple but unofficial/fragile endpoints: Spotify web-player token (https://open.spotify.com/api/token with TOTP secrets from raw.githubusercontent.com/xyloflake/spot-secrets-go), spclient.wg.spotify.com/canvaz-cache/v0/canvases protobuf, open.spotify.com/embed scraping for explicit flag and artist names; NetEase and LRCLIB lyric APIs; iTunes Search. Everything else is PUBLIC and confirmed linked/imported: CoreAudio process taps (CATapDescription, AudioHardwareCreateProcessTap/AggregateDevice, kAudioHardwarePropertyProcessObjectList/TranslatePIDToProcessObject, kAudioProcessPropertyBundleID/PID/IsRunningOutput; macOS 14.2+, NSAudioCaptureUsageDescription present in plist.json), CoreAudio volume/route properties (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar/Mute/TransportType), Accelerate vDSP biquads, MusicKit (MusicAuthorization, MusicCatalogSearchRequest, MusicDataRequest — needs a MusicKit-capable App ID; NSAppleMusicUsageDescription present), AVFoundation (AVQueuePlayer/AVPlayerLooper/AVPlayerLayer), CoreImage (CIGaussianBlur, CIAreaAverage), Metal/MetalKit (linked; visualizer.metal is a trivial passthrough with no music call site), Lottie.framework (embedded, for the optional Lottie visualizer), NSHapticFeedbackManager, URLSession/URLSessionWebSocketTask, Keychain SecItem*, ASWebAuthenticationSession (Spotify PKCE), MacroVisionKit (third-party window scan). dlopen/dlsym and CGEventTapCreate in macho.json belong to the HUD subsystem (DisplayServices/CoreBrightness dynamic loading, MediaKeyInterceptor), not to playback.
