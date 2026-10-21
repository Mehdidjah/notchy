#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Notchy"
BUNDLE_ID="com.local.Notchy"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# script/release.sh builds into its own folder, as a universal binary, without stopping a
# running copy.
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
UNIVERSAL="${UNIVERSAL:-0}"
KEEP_RUNNING="${KEEP_RUNNING:-0}"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
# Public GitHub repository (owner/name) whose releases the app checks for updates.
UPDATE_REPOSITORY="${UPDATE_REPOSITORY:-Mehdidjah/notchy-releases}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# Optimised build for normal runs: a debug build animates far more slowly. The debugger and
# the expanded preview (DEBUG-only seed data) keep the debug configuration.
case "$MODE" in
  --debug|debug|--preview|preview) CONFIGURATION="debug" ;;
  *) CONFIGURATION="release" ;;
esac

if [[ "$KEEP_RUNNING" != 1 ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  # The app was called NotchIsland; stop an old copy so it releases the clipboard store.
  pkill -x NotchIsland >/dev/null 2>&1 || true
fi

BUILD_ARGS=(--package-path "$ROOT_DIR" -c "$CONFIGURATION")
if [[ "$UNIVERSAL" == 1 ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BUILD_BINARY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Face Check's face-descriptor model (dlib's public-domain ResNet, converted by
# script/face-model/convert.py) ships compiled in Resources with its licence note. Without
# Xcode's coremlcompiler the app still builds, and Face Check reports the model as missing.
install_face_model() {
  local model_dir="$ROOT_DIR/Sources/Notchy/Features/FaceCheck/Model"
  local resources="$APP_CONTENTS/Resources"
  if ! xcrun --find coremlcompiler >/dev/null 2>&1; then
    echo "warning: coremlcompiler not found (it comes with Xcode); Face Check will be unavailable" >&2
    return 0
  fi
  mkdir -p "$resources"
  xcrun coremlcompiler compile "$model_dir/FaceDescriptor.mlpackage" "$resources" >/dev/null
  cp "$model_dir/MODEL-LICENSE.md" "$resources/FaceDescriptor-LICENSE.md"
}
install_face_model

# The app icon, made from Assets/AppIcon/artwork.png by script/app-icon/make-icon.sh.
mkdir -p "$APP_CONTENTS/Resources"
cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$APP_CONTENTS/Resources/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>NotchyUpdateRepository</key>
  <string>$UPDATE_REPOSITORY</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Notchy reads and controls Music and Spotify playback to show it in the notch.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Notchy shows today's events and upcoming meetings in the notch.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Notchy shows today's events and upcoming meetings in the notch.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>Notchy lists today's reminders beside your events.</string>
  <key>NSRemindersUsageDescription</key>
  <string>Notchy lists today's reminders beside your events.</string>
  <key>NSCameraUsageDescription</key>
  <string>Notchy shows a camera mirror in the notch when you turn it on.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Notchy shows when an app is using the microphone.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Notchy draws a live audio visualizer for the music that is playing.</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Notchy shows when Bluetooth headphones connect and their battery level.</string>
  <key>NSLocationUsageDescription</key>
  <string>Notchy shows the weather where you are on its Home tab.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Notchy shows the weather where you are on its Home tab.</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --preview|preview)
    /usr/bin/open -n "$APP_BUNDLE" --args --expanded-preview
    ;;
  --build|build)
    ;;
  --perf|perf)
    # Opens the island and steps through every tab, then quits; record it with Instruments,
    # e.g. xcrun xctrace record --template 'Animation Hitches' --launch -- "$APP_BINARY" --perf-cycle-tabs
    "$APP_BINARY" --perf-cycle-tabs
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify|--preview|--perf]" >&2
    exit 2
    ;;
esac
