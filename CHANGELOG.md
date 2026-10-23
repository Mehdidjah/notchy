# Notchy 1.0.2

- Integrated face, camera, recognition and password controls into the existing
  Settings → Face Check page.
- Use the circular nine-position camera guide for face setup and recapture;
  removed the duplicate settings entry that opened the older verification popup.
- Manage named identities, view capture quality, enable or disable a face, and
  replace its captures only after a complete successful scan.
- Choose cameras for built-in and external displays, with explicit handling for
  disconnected cameras, plus recognition confidence and detection distance.
- Configure experimental unlocking with wake, lock and spacebar triggers,
  retries, haptics, scan duration, and Minimal or Original animation.
- Added password-session inactivity expiry and Light or Heavy liveness options.
  Turning liveness off pauses automatic unlocking; Heavy also requires a blink
  or a small head turn.
- Cancel active checks immediately when their settings change and reject late
  results from the previous configuration.
- Added a menu-bar visibility control and kept face setup in the existing flow.

Automatic Mac Face Unlock remains restricted to explicitly enabled personal
testing builds until the separate recognition and photo/video validation trials
pass. It is not enabled in this standard 1.0.2 installer. Webcam checks do not
provide hardware biometric security.

This installer supports Apple silicon and Intel Macs running macOS 14 or later.
Quit Notchy before replacing an installed copy. This build is ad-hoc signed and
not notarized; first launch may require Open Anyway in System Settings → Privacy
& Security, and Camera or Accessibility permission may need to be renewed.

This release is public. Installed copies can discover it through their update
check; the installer can also be downloaded from the repository's Releases page.

# Notchy 1.0.1

- Guided face enrollment with a mirrored camera preview, nine ordered poses,
  directional progress, and a saved-face animation.
- Local, versioned recognition with AuraFace and two passive photo/screen models;
  existing encrypted face records are preserved.
- Fixed the camera-cleanup crash after long scans and improved positioning guidance.
- Added experimental Mac Face Unlock with encrypted password binding, system
  authorization, a compact lock-screen animation, and hover-to-retry.
- Fixed password submission on secure fields that omit character counts and
  preserved authorization across successful repeated unlocks.
- Show the actual camera, permission, or password-entry failure in the notch.

Automatic Mac Face Unlock remains restricted to explicitly enabled personal
testing builds until the separate recognition and photo/video validation trials
pass. It is not enabled in this standard 1.0.1 installer. Webcam checks do not provide
hardware biometric security.

This installer supports Apple silicon and Intel Macs running macOS 14 or later.
Quit Notchy before replacing an installed copy. Ad-hoc signed builds require
Open Anyway on first launch and may require Camera and Accessibility permission
to be granted again after an update.

This release is private. Downloading its installer requires access to the source
repository; automatic update checks and the public website cannot download it.
