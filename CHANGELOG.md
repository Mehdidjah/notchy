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
