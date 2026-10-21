# Notchy

A macOS menu-bar app that turns the MacBook notch into a Dynamic Island. The
island opens into a tabbed panel with Home, Shelf, Timer, Stats, Notes, Face Check,
and Clipboard. The interaction model (hover swell,
dwell-to-open, click, two-finger swipe, springs, radii, fullscreen retraction)
is built to feel native to the notch.

## Requirements

- macOS 14 or newer (a MacBook with a notch for the fused look; other displays
  get a 150-pt island at menu-bar height)
- Xcode 16 or newer with Command Line Tools, Swift 6.2 toolchain

## Build and run

```sh
./script/build_and_run.sh
```

Optional modes:

```sh
./script/build_and_run.sh --verify     # build, launch, confirm the process is running
./script/build_and_run.sh --debug      # run under lldb
./script/build_and_run.sh --logs       # launch and stream the process log
./script/build_and_run.sh --telemetry  # launch and stream the com.local.Notchy subsystem
./script/build_and_run.sh --preview    # launch pinned open with sample clips
swift test                             # unit tests
```

The script builds the Swift package, stages `dist/Notchy.app`, stops any
previous instance, and launches the new build. The bundle is unsigned, so the
Accessibility grant used for pasting may need to be renewed after rebuilding.

The app icon is `Assets/AppIcon/AppIcon.icns`, made from the square artwork in
`Assets/AppIcon/artwork.png`. After changing the artwork, run
`./script/app-icon/make-icon.sh` and commit both files; it fits the artwork into
the rounded square macOS uses for app icons. `script/release.sh` also gives the
disk image's volume this icon (with Xcode's `SetFile`).

## What it does

- **Island.** A fixed transparent strip at the top of the notch display hosts a
  black island drawn by SwiftUI. Clicks outside the island pass through to the
  app underneath and the island never activates itself. Hover swells the closed
  notch with a haptic tap and opens it after 0.3 s; a click opens it at once; a
  two-finger swipe down opens and a swipe up closes; the shelf folds away 0.1 s
  after the pointer leaves. It stays on all Spaces and over fullscreen apps, and
  can retract while a fullscreen app is active or hide from screen recordings.
- **Clipboard tab.** Everything copied in any app is captured locally into a
  SwiftData store with payloads on disk, classified (text, link, code, colour,
  image, file, …), checked for secrets, and shown as a card grid. Tap to paste
  into the app you came from (Accessibility permission) or copy, hover to delete,
  drag a card straight into another app. A newly captured clip peeks under the
  notch for 1.5 s.
- **Other tabs.** Shelf (file drop tray with Quick Look and AirDrop), Timer and
  Stats appear as they land. Each can be hidden in
  Settings.
- **Windows.** Quick Paste panel, a full Clipboard Library window with grid,
  list and board views, and a Settings window (General, Capture, Notch, History,
  Privacy, Permissions).
- **Face Check.** Scan in the Face tab, blink and follow the head-turn prompt,
  then capture the enrollment poses. Successful storage plays a native “Face
  saved” animation. “Check now” and protected clipboard actions open a scan in
  the notch, followed by a recognized or retry state. Failed checks support
  hover-to-retry for five seconds. A small check window appears if the notch is
  hidden. Camera processing and encrypted face descriptors stay on this Mac.

Sensitive clipboard items start hidden in every view. Face Check reveals an
item for 60 seconds; app deactivation hides revealed content again.
Copy, paste, drag, combined paste, and queued paste enforce the same gate.
Clearing history requires a fresh check when a face is enrolled. Adding or
deleting saved faces also requires a check; unavailable face data can be reset
through macOS owner authentication.

Every match setting requires a fresh blink, a randomly requested head turn,
non-planar nose motion, and a return to center. Large reflections on the face
and enclosing device outlines reject the attempt. These RGB-camera heuristics
need testing with the actual camera and lighting; they do not guarantee rejection
of every photo or replayed video. See [Face Check validation](docs/face-check.md).

## Layout

- `Sources/Notchy/App` entry point and app delegate
- `Sources/Notchy/Models` value types, state machine, settings, tabs
- `Sources/Notchy/Services` clipboard monitor, normaliser, repository,
  paste coordinator, fullscreen detector, haptics
- `Sources/Notchy/Stores` the island view model
- `Sources/Notchy/Support` panel controller, geometry, composition root,
  window controllers, menu bar
- `Sources/Notchy/Views` island shell, tabs, library, quick paste, settings
- `Sources/Notchy/Features/<Feature>` self-contained feature tabs
- `Tests/NotchyTests` Swift Testing suite
