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

On a clean checkout, generate the pinned recognition model using
[the model preparation guide](script/face-model/AURAFACE.md) before scanning a face
or building a release. The smaller passive-screening models are included in the
repository. Inference runs locally with Core ML.

The script builds the Swift package, stages and ad-hoc signs the complete
`dist/Notchy.app` bundle, stops any previous instance, and launches the new build.
The Accessibility grant used for pasting and optional Mac unlock may need to be
renewed after rebuilding. If Notchy is missing from the permissions list, use
**+** to add the exact `.app` you are running; a copy in `~/Applications` is easier
to find than a temporary build.

The app icon comes from the square artwork in `Assets/AppIcon/artwork.png`.
`./script/app-icon/make-icon.sh` splits it into the layers of a Liquid Glass icon
(`Assets/AppIcon/AppIcon.icon`: the wordmark and the band with its notch as glass
over the gradient) and makes a flat `AppIcon.icns` for macOS before 26; run it
after changing the artwork and commit the results. The build compiles the glass
icon with Xcode 26's `actool` and falls back to the flat one without it.
`script/release.sh` also gives the disk image's volume the icon (with Xcode's
`SetFile`).

## Releases

Notchy is distributed as a disk image, `Notchy.dmg`. Releases in
`Mehdidjah/notchy` are currently private, so downloading them requires repository
access. Automatic app update checks and the public website cannot access private
releases. Set `UPDATE_REPOSITORY` to a public release host for public distribution.

To prepare a version, raise `VERSION`, commit, and build:

```sh
./script/release.sh            # build dist/release/Notchy-<version>.dmg to try first
RELEASE_NOTES=CHANGELOG.md ./script/release.sh --publish  # public repositories only
```

For a private release, upload the verified installer through GitHub Releases
under the fixed asset name `Notchy.dmg`, with `CHANGELOG.md` as the release notes.
The publishing script deliberately requires a public host for automatic updates.

The image opens on a window with the app, an arrow and the Applications
folder. Finder lays that window out, so the first run asks to let the terminal
control Finder.

With a public release host, a website can use its stable asset link:

```text
https://github.com/Mehdidjah/notchy/releases/latest/download/Notchy.dmg
```

which serves the newest release (the download page in `website/` uses it),
and can read the newest version number from
`https://api.github.com/repos/Mehdidjah/notchy/releases/latest`
(`tag_name`). Installed copies check the same release every 30 minutes and,
once per version, show an update peek under the notch and a notification that
downloads the new image when clicked; the menu bar and Settings → About offer
the download too.

Without a Developer ID, the app is ad-hoc signed: on first launch macOS says it
can't verify Notchy, and users allow it in System Settings → Privacy & Security
→ Open Anyway; it also asks for its permissions again after each update. With
an Apple Developer account, set `SIGN_IDENTITY` and `NOTARY_PROFILE` to sign
and notarize the image so it opens without that step.

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
- **Face Check.** Scan in the Face tab with a circular camera guide and blue
  progress ring at the top of the screen. Follow nine ordered head positions,
  with two stable captures per pose and passive photo/screen checks. Successful
  storage plays a native “Face saved” animation. Protected clipboard actions use
  the same circular camera presentation with a recognized or retry state. Failed checks support
  hover-to-retry for five seconds. A small check window appears if the notch is
  hidden. AuraFace handles all recognition; the retired model is no longer bundled.
  Existing AuraFace captures remain usable; older faces require recapture in Settings.
  Camera processing and encrypted face descriptors stay on this Mac.
- **Optional Mac Face Unlock.** Choose **Set up Face Unlock** in the Face tab.
  The circular scan saves your face, then the same notch panel asks for your Mac
  login password. **Save & enable** validates and encrypts it with system authentication.
  Recapturing a face uses macOS owner authentication before scanning. A separate
  lock-screen check verifies your face and passive photo/screen checks before entering the
  encrypted password. Authorize once per Notchy launch and keep the app running.
  The first login after restarting or logging out remains manual. Normal builds
  require a passing live-camera evaluation report before password setup or unlock.
  An explicit `EXPERIMENTAL_FACE_UNLOCK=1` local build enables personal testing
  with the same face and photo/screen checks, marked experimental in the UI;
  it does not count as validation and cannot be packaged by the release script.
- **Face Check settings.** The existing Face Check pane includes
  wake/lock/spacebar triggers, display and camera routing, retries, haptics,
  scan duration, and Minimal or Original animation. Manage named encrypted
  identities, recapture them atomically, and change or remove the bound password.
  Password authorization expires after the selected inactivity period or app exit.
  Light liveness uses passive photo/screen checks; Heavy also requires a blink or
  small head turn. Turning liveness off pauses Mac unlocking. The spacebar option
  needs Input Monitoring permission and listens only while the Mac is locked.

Sensitive clipboard items start hidden in every view. Face Check reveals an
item for 60 seconds; app deactivation hides revealed content again.
Copy, paste, drag, combined paste, and queued paste enforce the same gate.
Clearing history requires a fresh check when a face is enrolled. Adding or
deleting saved faces also requires a check; unavailable face data can be reset
through macOS owner authentication.

Protected in-app checks require a fresh blink, a randomly requested head turn,
non-planar nose motion, and a return to center. Large reflections on the face
and enclosing device outlines reject the attempt. These RGB-camera heuristics
need testing with the actual camera and lighting; they do not guarantee rejection
of every photo or replayed video.

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
- `Tests/NotchyTests` Swift Testing suite, kept on the developer's Mac and not in the repository
