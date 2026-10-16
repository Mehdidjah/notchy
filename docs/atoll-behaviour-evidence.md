# Atoll notch behaviour: evidence ledger

Date: 2026-10-15

NotchIsland's notch interaction (hover swell, dwell-to-open, click-to-open,
swipe-to-open/close, open/close springs, shadow, corner radii, capture peek,
fullscreen retraction) was reworked to match the shipped Atoll app. This file
records where each behaviour was established so the implementation can be
audited and re-checked after Atoll updates.

Atoll is GPL-3.0. NotchIsland reimplements the observed behaviour in its own
code; no Atoll source was copied. Parameters (timings, radii, spring values)
are facts about behaviour, not expression, and are listed below.

## Sources

| Source | Identity | Use |
| --- | --- | --- |
| Installed binary | `/Applications/Atoll.app` 2.3.3, main executable SHA-256 `ea6d4ace3555afce31f341182a173fd48b00cded42c4de05ac914cf41534edaa` | What actually ships |
| Source clone | `github.com/Ebullioscopic/Atoll` at `868c25d` (2026-10-15) | Exact logic and constants |
| Live window listing | `CGWindowListCopyWindowInfo` while Atoll 2.3.3 ran | Window level and size |

## REA evidence records

REA (`rea-agents` 6.5.0, run with the nvm Node 24.19 install because the
Homebrew Node is broken on this Mac) produced the following records. The JSON
files live in the session scratchpad and can be regenerated with the commands
in the last section.

| Operation | Evidence ID | Subject |
| --- | --- | --- |
| `inspect_signature` | `ev_7091810b98516e051ab3d1dca37c6eff20a702d74e1c0d53dbb974f2b00a701a` | main executable |
| `inspect_plist` | `ev_ee28ad85eea8bd533befb8b3c8c4ef2c5ab9436ed18ae003d0bcb7a72cb07073` | main executable |
| `inspect_macho` | `ev_decbeec3f8ae7bd6f734b60475c1cf361231d25befa4598526864cf91adf0330` | main executable, arm64 slice |
| `inspect_analysis_view` (summary) | `ev_33297f413e88c3ed64f3ac8a049b8daa55ee2a8b0e2a4eb834eb24b6a05d901d` | view of the Mach-O record |
| `inspect_native_dispatch_metadata` | `ev_db712680668ec3cf14ec61c3000ac7a7f08686a34498f74054bca3d30de7d049` | main executable |
| `trace_dylib_resolution` | `ev_4f3ec0ca4bdad9ae9eb6ec44a0bdec0a0dfe0e46acd970fd37b5e8f9972b662e` | app bundle |
| `inspect_artifact` | `ev_3db3ce9c63c8af611b1498c6995954dc25871eefa05dfd9f416628deaa8b9073` | app bundle, root SHA-256 `c3a49466…aad758` |
| `project_apple_application_graph` | `ev_3f1b5a8be37ea4d5c9d7c667b06a309000f8340f52c1a7da21686e8633fd9224` | app bundle |
| `inspect_asset_catalog` | `ev_46af713f5075b0bed3d20db9dbf55236552e844e19762664e6dce54c308b6ea8` | `Contents/Resources/Assets.car` |

`observe_native_ui` refused Atoll's notch panel (`window-mismatch`). REA's helper only
accepts normal-level windows (`bridge/native/ReaNativeUI.swift:65-71` requires
`kCGWindowLayer == 0`) and Atoll's panel sits at layer 27, so REA cannot observe it by
design; a direct Accessibility dump also needs the observing process to be trusted. Live
rendering was checked with screen captures and a user-supplied screenshot
(`atoll-specs/reference/atoll-home-standalone-calendar.png`).

The compiled asset catalog holds no named colours: Atoll's accent is the system accent
colour. Images are the app icon variants, brand logos, `bolt`/`plug` (battery charging
glyphs), `sparkle`, `spotlight` and desktop wallpapers used in onboarding. Pseudocode was not
produced because no Hopper, Ghidra, or IDA engine is installed; none was needed
because the source is public.

## Observations from the binary

These come from the Mach-O imports and dispatch metadata above and are
observations, not inferences.

- Signed with Developer ID (team `9Y64TRM77N`), hardened runtime, notarizable.
  Not sandboxed. Entitlements include Apple Events automation, camera,
  calendars, location, and a Mach service.
- Imports private window-server symbols `CGSSpaceCreate`,
  `CGSSpaceSetAbsoluteLevel`, `CGSAddWindowsToSpaces`, `_CGSDefaultConnection`
  and `SLS*` SkyLight symbols. Classes `NotchSpaceManager` and `CGSSpace` exist.
  This is how Atoll keeps the notch above fullscreen Spaces and the menu bar.
- Imports `NSHapticFeedbackManager` (hover and click haptics).
- Imports `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`,
  `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`
  (fullscreen confirmation through the `AXFullScreen` attribute).
- Imports `CGWindowListCopyWindowInfo` (window-geometry fallback).
- Imports Carbon `RegisterEventHotKey`, `UnregisterEventHotKey`,
  `InstallEventHandler` and bundles the KeyboardShortcuts package resources
  (global shortcuts).
- Imports `NSTrackingArea`, `CGShieldingWindowLevel`, `CGWindowLevelForKey`,
  and the `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` accessors.
- Bundles Sparkle (updater XPC services), Lottie, SwiftTerm, Defaults, and a
  private `MediaRemoteAdapter.framework` in Resources.
- While running, the notch window sat at window-server layer 27, which is
  `NSWindow.Level.mainMenu + 3`, 640 by 218 points, centred on a 1728-point
  display, with its other windows off screen.

## Behaviour adopted in NotchIsland

| Behaviour | Value | Established by | NotchIsland |
| --- | --- | --- | --- |
| Hover dwell before open | 0.3 s | `Constants.swift` `minimumHoverDuration` | `UserSettings.hoverDelayMilliseconds` default 300 |
| Hover-exit grace before close | 100 ms | `ContentView.swift` `handleHover` | `UserSettings.closeDelayMilliseconds` default 100 |
| Collapsed swell on hover | +8 pt width and height | `ContentView.swift` closed layout | `NotchSilhouette.hoverSwell` |
| Hover animation | `.bouncy.speed(1.2)` | `ContentView.swift` | `NotchRootView.hoverAnimation` |
| Open animation | spring response 0.42, damping 1.0 | `ContentView.swift` | `NotchRootView.openAnimation` |
| Close animation | spring response 0.45, damping 1.0 | `ContentView.swift` | `NotchRootView.closeAnimation` |
| Content transition | `.blurReplace` with interactive spring | `ContentView.swift` | `NotchRootView` |
| Shadow | black 0.6, radius 10, when open or hovered | `ContentView.swift` | `NotchSilhouette.shadow*` |
| Corner radii closed | top 6, bottom 14 | `matters.swift` `cornerRadiusInsets` | `NotchSilhouette.closed*` |
| Corner radii open | top 19, bottom 24 | `matters.swift` | `NotchSilhouette.open*` |
| Collapsed size | hardware gap + 4 wide by the safe-area height; 150 wide by the menu-bar height on displays without a notch | `matters.swift` `getClosedNotchSize`, `Constants.swift` `closedNotchWidth`, `nonNotchHeightMode` | `NotchGeometry.syntheticOrHardwareWidth`, `NotchGeometryResolver.resolve` |
| Haptic | alignment tap, 300 ms rate limit, on hover enter, click, swipe | `ContentView.swift`; Mach-O import | `NotchViewModel.triggerHaptic` |
| Click opens at once | tap and global/local mouse-down monitor, accepted only on the drawn notch plus 24 pt horizontal and 6 pt vertical slack (the wider hover band only arms a dwell) | `ContentView.swift` `startHoverClickMonitor`, `isMouseOverClosedNotchHitArea` | `NotchPanelController.handleMouseDown`, `NotchPresentationMetrics.activationSize` |
| Swipe to open/close | accumulate scroll deltas, ignore momentum, noise 0.2, sensitivity 200, progress = travel/sensitivity × 20; the close swipe needs trackpad phases and vertical dominance so card-row scrolling is left alone; progress resets after a 300 ms pause or on any state change | `PanGesture.swift`, `handleScrollGesture`, `isScrollGestureActive` | `NotchPanelController.handleScroll`, `updateOpenGesture`, `updateCloseGesture` |
| Top-edge hover retention | inclusive top pixel | `ContentView.swift` `shouldRetainHoverAtScreenTopEdge` | `NotchGeometryResolver.rectContainsIncludingTopEdge` |
| Window | non-activating panel, level `mainMenu + 3`, all Spaces, fullscreen auxiliary, no shadow, key-capable; keyboard focus handed back when the shelf folds | `DynamicIslandWindow.swift`; live listing (layer 27) | `NotchPanelController.configure`, `releaseKeyboardIfNeeded` |
| Hide from screen capture | `sharingType = .none` when enabled | `ScreenCaptureVisibilityManager.swift` | `UserSettings.hideFromScreenCapture` |
| Fullscreen hiding | per-screen: owners of screen-filling windows on the island's display, `AXFullScreen` on their windows with a 0.25 s messaging timeout, else a visible-menu-bar test (matched by owner and level, not name); 500 ms settle | `FullscreenMediaDetection.swift`; Mach-O imports | `FullscreenDetector` |
| Transient surface | sneak peek / live activity on the closed notch | `DynamicIslandViewCoordinator.swift` | capture peek (`presentCapturePeek`), 1.5 s |

## Deliberately not adopted

- Private `CGSSpace` and SkyLight APIs. NotchIsland stays on public AppKit:
  a full-width transparent panel at `.statusBar` level with pass-through hit
  testing, which is what keeps clicks outside the island reaching other apps.
- `MediaRemoteAdapter`, lock-screen widgets, stats, and the rest of Atoll's
  media stack. They are outside NotchIsland's scope and rely on private
  frameworks.
- Atoll's window is resized to the island on every open and close. NotchIsland
  keeps one fixed strip and animates inside it, which avoids per-frame window
  transactions.

## Known trade-offs

- The open shelf's drop shadow paints partly opaque pixels up to 10 pt outside the
  island. The window server routes a click on those pixels to the island, which
  ignores it, so the app underneath does not receive it either. Atoll has the same
  halo. Turning off "Shadow while open" removes it.
- Review on 2026-10-15 (five-dimension adversarial pass) confirmed and led to: the
  activation slack above, the menu-bar-height island on notch-less displays, the
  `mainMenu + 3` level, keyboard hand-back, the per-screen fullscreen detector,
  no-op `setFullscreen` calls leaving timers alone, gesture reset on pause or state
  change, the close-swipe scroll guard, and a 100 ms grace for the armed hover.

## Unknowns

- Atoll's exact menu-bar clearance logic for live activities was not compared;
  NotchIsland's closed notch never extends into the menu strip, so it does not
  apply.
- The scroll sign convention assumes the default natural scrolling direction,
  as Atoll's gesture code does. A reversed trackpad setting flips it.

## Regenerating the REA records

```sh
export PATH="$HOME/.nvm/versions/node/v24.19.0/bin:$PATH"
APP=/Applications/Atoll.app
BIN=$APP/Contents/MacOS/Atoll
npx -y rea-agents@6.5.0 inspect-signature "$APP" --json > signature.json
npx -y rea-agents@6.5.0 inspect-plist "$APP" --json > plist.json
npx -y rea-agents@6.5.0 inspect-macho "$BIN" --json > macho.json
npx -y rea-agents@6.5.0 inspect-native-dispatch-metadata "$BIN" --max-records 20000 --json > dispatch.json
npx -y rea-agents@6.5.0 trace-dylib-resolution "$APP" --json > dylib.json
npx -y rea-agents@6.5.0 inspect-artifact "$APP" --json > artifact.json
```
