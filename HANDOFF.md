# Notchy — handoff

Status as of 2026-10-16. Read this before changing anything; the "Rules" section reflects the owner's explicit preferences.

## What Notchy is

A macOS 14+ notch app ("dynamic island" for the MacBook notch): a clipboard manager at its core, plus tabs and live activities shown in an island drawn around the hardware notch. SwiftPM project, Swift 6.2 with strict concurrency, SwiftUI hosted in a borderless non-activating `NSPanel`. No Xcode project.

- Repo: `github.com/Mehdidjah/notchy` (private), branch `main`. Local folder is still named `dynamic-island`.
- The app was called NotchIsland until 2026-10-16. `Support/LegacyDataMigration.swift` moves the old Application Support folder and settings on first launch; don't remove it yet.

## Build, run, test

```bash
./script/build_and_run.sh            # release build into dist/Notchy.app, then launch (kills a running copy)
./script/build_and_run.sh --build    # build the bundle only
./script/build_and_run.sh --debug    # debug build under lldb
./script/build_and_run.sh --perf     # release build, cycles through the tabs, prints frame timings, quits
swift build
swift test                           # 575 tests (Swift Testing)
swift test --filter FaceCheck        # one area
```

- Normal runs use the **release** configuration on purpose: debug builds animate far worse.
- The owner asked to stop the app during this session. It was left stopped; use `--build` for further checks and do not relaunch until asked.
- The build script writes Info.plist (bundle id `com.local.Notchy`, privacy usage strings) and compiles the face model into `Contents/Resources` with `xcrun coremlcompiler` (needs Xcode).
- The app is **unsigned (ad-hoc)**, so macOS forgets permissions (camera, Calendar, Accessibility, Automation) after every rebuild. This is expected.
- Known timing-flaky tests that fail only under the full parallel run and pass alone: `FocusTests` toastMode* and `modeSwitchDuringTheToastSnapsShutThenReopens`, `TimerTests.closedNotchLabelFlashesOnStartAndHoldsOnceFinished`, `StatsTests.repeatedStateReportsDoNotRestartPendingTimers`, `StatsManagerTests.monitoringStartsAfterTheDelayAndStopsOnTabSwitch`. Fixing them (replace fixed sleeps with polling, as `NotchViewModelTests` does with `eventually`) is on the backlog.

## Rules (owner preferences — follow them)

1. **Git:** separate logical commits (one per feature or request) **directly on `main`**, then push. No feature branches unless asked. Commit and push before deleting anything. Leave `.vscode/` uncommitted.
2. **Never name other apps** anywhere in the repo: code, comments, identifiers, tests, docs, UI text, commit messages. Describe behaviour directly ("open spring response 0.42"), not "like app X". Identifiers use neutral names (`designColumns`, `expected…`).
3. **Original code only.** Behaviour may be studied from other apps, but never copy their code or assets (videos, images).
4. **Public macOS APIs only.** No private frameworks (no SkyLight/CGS/DisplayServices, no `dlopen` tricks).
5. **Every tab keeps Home's height** (`NotchTab.standardOpenHeight` = 200). Only Stats may grow for extra graph rows. Never let a feature grow the island.
6. **Smoothness matters.** Nothing per-frame on the main actor; measure with `--perf` before and after UI changes.
7. **Out of scope:** unlocking macOS at the lock screen (storing the login password and typing it). It was requested and declined; Face Check stays an in-app feature. Don't implement it.

## Architecture map

```
Sources/Notchy/
  App/            NotchyApp.swift (entry, AppDelegate, runs LegacyDataMigration)
  Live/           IslandActivityCenter (ClosedLiveActivity priority chain, SneakPeek requests), HomeLayoutState
  Models/         NotchState (state machine), NotchTab, UserSettings, clipboard models
  Services/       clipboard monitor/repository/paste, permissions, fullscreen detector, haptics
  Stores/         NotchViewModel (island state, tabs, hover/gesture, holds, sizes)
  Support/        AppEnvironment (wires everything), NotchPanelController (panel, hit testing, scroll/click
                  monitors), NotchGeometryResolver (sizes), Settings/Library/QuickPaste window controllers,
                  PerfTabCycler (--perf-cycle-tabs), LegacyDataMigration
  Views/          NotchRootView (silhouette, closed wings, sneak peek), NotchShellView (tab bar + tab content),
                  NotchClipboardTabView, SettingsView (sidebar panes + SettingsSectionRegistry), Library, QuickPaste
  Features/<Name>/  one folder per feature
```

Extension points features use:
- **Closed-notch wings:** conform to `ClosedLiveActivity` and register with `IslandActivityCenter.shared` (priority constants in `ClosedActivityPriority`).
- **Sneak peeks:** `IslandActivityCenter.shared.requestSneakPeek(SneakPeek(...))`.
- **Settings:** `SettingsSectionRegistry.shared.register(.pane, id:) { SectionView() }`; panes live in the `SettingsPane` enum.
- **Island hooks on `NotchViewModel`:** `holdOpen(reason:)`/`releaseHold`, `extraOpenHeightProvider` (Stats only), `liveActivityTabProvider`, `openSizeDidChange`.
- **Tabs:** `NotchTab` enum + `availableTabs` in `NotchViewModel` + `UserSettings.show…Tab` + the switch in `NotchShellView`.

## Feature status

Started in `AppEnvironment.startFeatures()` (working): Timer, Color Picker, Stats, Shelf, Media (Apple Music/Spotify), Calendar (+ reminder activity), System HUDs (volume, brightness, mic, Caps Lock), Face Check settings page. Tabs shown: Home, Shelf, Timer, Stats, Notes, Face Check, Clipboard.

**Built and tested but not started/wired yet** (each folder has its own tests; integration hooks are still to add in `AppEnvironment`, the header and settings): Battery, Bluetooth, Privacy (camera/mic in use), Downloads, Focus, Notes (tab view is shown, its feature/settings are not started), Mirror (Home slot is used; settings not registered), Caffeinate, Shortcuts, Onboarding (including a "hello" animation that should play inside the open island).

## Face Check (current focus)

An in-app face check, local only.

Done:
- `Model/FaceDescriptor.mlpackage`: dlib's public-domain face-recognition ResNet (128-d descriptors, 150×150 chips) converted with `script/face-model/` (original converter + parity check; see its README and `MODEL-LICENSE.md`). Parity with dlib is cosine ≥ 0.99998.
- `FaceEmbedder` (actor, own queue, CPU+Neural Engine), `FaceChipAligner`/`FaceChipRenderer`/`FaceChipTemplate` (dlib's 5-point chip geometry from Vision landmarks; Boost-licensed constants), `FaceMatcher` (template + closest-sample dual gate, strict/balanced/relaxed = 0.50/0.55/0.60), `FaceEnrollment` (nine-pose tracker), `FaceEnrollmentStore` (AES-GCM sealed JSON).
- `FaceCheckKeyStorage`: store key derived from a Secure Enclave key + a saved public peer (no keychain: the unsigned app can't use the data-protection keychain, and file-keychain items break on every rebuild).
- `FaceCheckCamera` (capture, drops frames while busy, timestamps before analysis, explicitly unmirrored output), `FaceCheckPipeline` (Vision → liveness cues → align → embed, own queue), `FaceCheckController` (preview ownership, enrollment, 10 s check timeout independent of camera frames, presets, saved faces).
- UI: Settings → System → Face Check page and `NotchFaceTabView`. Enrollment requires fresh liveness before saving; success only plays after persistence succeeds.
- `FaceCheckLiveActivity`, priority 35: native pill → blue breathing face → rotating rings → blue check, or dimmed face/shake for failure. `FaceCheckEmblem` draws original paths in an asynchronous Canvas. Expansion .45 s, success 1.7 s, failure 5 s with hover retry; haptics and Reduce Motion. `FaceCheckWindowController` presents the same controls when the notch is disabled/fullscreen-hidden. The performance harness measures each animation stage without authorizing actions.
- `FaceCheckAuthorizing` connects the controller to clipboard actions. Sensitive items are centrally redacted, including payload paths/search/previews. Grants last 60 s and are rechecked at export; replacement/deletion invalidates approvals. Clearing history requires a fresh check when enrollment exists. Face additions/deletions require checks; unusable enrollment can be reset with macOS owner authentication.
- `FaceLivenessTracker`: blink → random shoulder turn with nose parallax beyond a planar projective fit → return to center. Glare on the face and enclosing device outlines reject. Missing/invalid/multiple-face frames reset evidence. `FaceVerificationSession` requires the same enrolled identity throughout. All match presets require liveness.
- Tests cover liveness geometry/images/sequences, authorization/camera lifecycle, native presentation geometry, clipboard redaction/export/expiry and exactly-once callbacks. See `docs/face-check.md` for the manual camera matrix and optional snapshot command.

Next: real-camera calibration and spoof testing with the owner. Static/planar fixtures pass the automated rejection tests, but RGB heuristics cannot guarantee rejection of all photos or replayed videos. Left/right challenge signs follow unmirrored camera coordinates (left is positive yaw); the preview is mirrored separately. Vision pitch is negated at the enrollment boundary because its positive direction is down.

Open items from the code review: one model identifier source (use `FaceEmbedder.modelIdentifier` everywhere), a byte-exact renderer fixture test, `fsync` before the store's rename, make a `coremlcompiler` failure non-fatal under `set -e` in the build script, mention the Boost-licensed chip constants in the licence note. The enrolment grid's left/right mapping is unverified on a real camera; flip `FaceEnrollmentGrid.rows` if it fills on the wrong side.

## Performance notes

- The latest completed release tab run measured 8.3–8.4 ms worst frames outside Face; Face measured 29.1 ms, with two hitches/three dropped frames, versus 41.1 ms before this work. The new native-animation measurement run was interrupted when the owner requested that the app stop. An LLDB diagnostic run is not a release timing baseline; the new stages still need a normal `--perf` run when launching is authorized.
- Tab-switch worst frames (release build, 120 Hz) are about 8.3 ms on every tab except Home (~25 ms on first appearance; open item).
- Causes already fixed: the island shadow was cast from a composited group (CPU re-rasterisation every frame; now a separate silhouette), and the Settings/Library/Quick Paste windows kept live SwiftUI content observing the model while hidden (now built on show, released on close).
- Tried and rejected: keeping visited tabs alive between switches. It made revisits slower (30–60 ms frames), so it was not merged.

## Other backlog

- Focus feature starts `/usr/bin/log stream` processes that outlive the app or tests; terminate them on stop/exit.
- The brightness-key event tap runs on the main run loop; move it to a background thread.
- Wire the not-yet-started features listed above.
- Optional later: Terminal tab (would need a SwiftTerm package dependency), LLM-usage tab.

## History pointers

- Feature work landed in the commits from `de575be` onward (one commit per feature).
- The original behaviour notes and specs used to build the island were removed from the tree; they are in git history at commit `b742955` (`docs/`). Use them for behaviour only and keep rule 2 in mind.
