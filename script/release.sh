#!/usr/bin/env bash
# Packages Notchy into a disk image other Macs can install from, and optionally publishes it as
# a release that installed copies find through their update check.
#
#   script/release.sh            build dist/release/Notchy-<version>.dmg
#   script/release.sh --publish  also tag v<version> and upload the image as a GitHub release
#
# A published image is always named Notchy.dmg, so a website's download button can link to
# https://github.com/<UPDATE_REPOSITORY>/releases/latest/download/Notchy.dmg and serve each new
# version without changing. Installed copies check for it every 30 minutes and announce it.
#
# The image opens on a window that shows the app, an arrow and the Applications folder. Finder
# lays that window out, so the first run asks to let the terminal control Finder; without that
# the image keeps Finder's plain window.
#
# The version comes from VERSION; raise it before each release. Environment:
#   UPDATE_REPOSITORY  public owner/name the app checks and --publish uploads to
#                      (default Mehdidjah/notchy-releases); create it once with
#                      gh repo create <owner/name> --public --add-readme
#   SIGN_IDENTITY      a "Developer ID Application: …" identity; without one the app is ad-hoc
#                      signed and macOS asks users to confirm the first launch
#   NOTARY_PROFILE     a notarytool keychain profile; with SIGN_IDENTITY the image is notarized
#   RELEASE_NOTES      file with the release notes (default: commit subjects since the last tag)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Notchy"
VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
TAG="v$VERSION"
UPDATE_REPOSITORY="${UPDATE_REPOSITORY:-Mehdidjah/notchy-releases}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
DMG="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
# The name every release uploads its image under.
DOWNLOAD_NAME="$APP_NAME.dmg"
DOWNLOAD_LINK="https://github.com/$UPDATE_REPOSITORY/releases/latest/download/$DOWNLOAD_NAME"
# The install window, in points: its content size and the centres of the two icons.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
APP_ICON_X=170
APPLICATIONS_ICON_X=490
ICONS_Y=220

PUBLISH=0
case "${1:-}" in
  "") ;;
  --publish) PUBLISH=1 ;;
  *) echo "usage: $0 [--publish]" >&2; exit 2 ;;
esac

fail() { echo "error: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "VERSION must look like 1.2 or 1.2.3 (found '$VERSION')"

if [[ "$PUBLISH" == 1 ]]; then
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
  # HANDOFF.md is a local note and never part of a build.
  git -C "$ROOT_DIR" diff --quiet -- . ':(exclude)HANDOFF.md' \
    && git -C "$ROOT_DIR" diff --cached --quiet -- . ':(exclude)HANDOFF.md' \
    || fail "commit your changes first; a release is built from a committed tree"
  VISIBILITY="$(gh repo view "$UPDATE_REPOSITORY" --json visibility --jq .visibility 2>/dev/null || true)"
  [[ -n "$VISIBILITY" ]] || fail "$UPDATE_REPOSITORY doesn't exist; create it once with: gh repo create $UPDATE_REPOSITORY --public --add-readme"
  [[ "$VISIBILITY" == PUBLIC ]] || fail "$UPDATE_REPOSITORY is $(tr "[:upper:]" "[:lower:]" <<<"$VISIBILITY"); it must be public so installed copies and your website can see its releases"
  if gh release view "$TAG" --repo "$UPDATE_REPOSITORY" >/dev/null 2>&1; then
    fail "$TAG is already published in $UPDATE_REPOSITORY; raise VERSION"
  fi
fi
[[ ! -e "/Volumes/$APP_NAME" ]] || fail "eject the mounted $APP_NAME disk image first"

echo "==> Building $APP_NAME $VERSION (Apple silicon and Intel)"
rm -rf "$RELEASE_DIR"
DIST_DIR="$RELEASE_DIR" UNIVERSAL=1 KEEP_RUNNING=1 APP_VERSION="$VERSION" \
  UPDATE_REPOSITORY="$UPDATE_REPOSITORY" "$ROOT_DIR/script/build_and_run.sh" --build

echo "==> Signing"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT_DIR/script/Notchy.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --sign - "$APP_BUNDLE"
fi
codesign --verify --strict "$APP_BUNDLE"

echo "==> Creating $(basename "$DMG")"
WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
  [[ -z "$DEVICE" ]] || hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
STAGING="$WORK/staging"
mkdir -p "$STAGING/.background"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
for scale in 1 2; do
  swift "$ROOT_DIR/script/dmg/make-background.swift" "$WORK/background-$scale.png" "$scale" \
    "$WINDOW_WIDTH" "$WINDOW_HEIGHT" "$APP_ICON_X" "$APPLICATIONS_ICON_X" "$ICONS_Y"
done
tiffutil -cathidpicheck "$WORK/background-1.png" "$WORK/background-2.png" \
  -out "$STAGING/.background/background.tiff" >/dev/null 2>&1

# Room for the window settings Finder writes.
SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 20 ))
READ_WRITE="$WORK/$APP_NAME-rw.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size "${SIZE_MB}m" \
  -ov "$READ_WRITE" >/dev/null
# Mounted where Finder sees it, so Finder can lay out its window.
ATTACHED="$(hdiutil attach "$READ_WRITE" -readwrite -noverify -noautoopen)"
DEVICE="$(awk '/\/Volumes\// { print $1; exit }' <<<"$ATTACHED")"
MOUNT="$(awk -F '\t' '/\/Volumes\// { print $NF; exit }' <<<"$ATTACHED")"
[[ -n "$DEVICE" && -d "$MOUNT" ]] || fail "couldn't mount the disk image"
# Finder's window includes its title bar, so it is a little taller than the picture's content.
LEFT=200
TOP=120
RIGHT=$((LEFT + WINDOW_WIDTH))
BOTTOM=$((TOP + WINDOW_HEIGHT + 28))
# Stops waiting after two minutes, for example when nobody answers the permission prompt.
if perl -e 'alarm shift; exec @ARGV' 120 osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$(basename "$MOUNT")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {$LEFT, $TOP, $RIGHT, $BOTTOM}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to false
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $ICONS_Y}
    set position of item "Applications" of container window to {$APPLICATIONS_ICON_X, $ICONS_Y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  sync
  [[ -f "$MOUNT/.DS_Store" ]] || echo "warning: Finder didn't save the window layout; the image opens on a plain window" >&2
else
  echo "warning: couldn't lay out the window (allow the terminal to control Finder in System Settings → Privacy & Security → Automation); the image opens on a plain window" >&2
fi
# The mounted image wears the app icon. Finder drops a volume icon while it lays out the window,
# so it goes in afterwards. Marking the volume as having a custom icon takes SetFile, which
# comes with Xcode; without it the image just has the standard disk icon.
cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "$MOUNT"
  xcrun SetFile -a V "$MOUNT/.background"
else
  echo "warning: SetFile not found (it comes with Xcode); the disk image keeps the standard icon" >&2
fi
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
for attempt in 1 2 3 4 5; do
  hdiutil detach "$DEVICE" >/dev/null 2>&1 && break
  [[ "$attempt" == 5 ]] && hdiutil detach "$DEVICE" -force >/dev/null
  sleep 1
done
DEVICE=""
hdiutil convert "$READ_WRITE" -format ULFO -ov -o "$DMG" >/dev/null

NOTARIZED=0
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    NOTARIZED=1
  fi
fi

echo "==> $DMG"
shasum -a 256 "$DMG"

[[ "$PUBLISH" == 1 ]] || exit 0

NOTES="$WORK/notes.md"
if [[ -n "${RELEASE_NOTES:-}" ]]; then
  cp "$RELEASE_NOTES" "$NOTES"
else
  PREVIOUS_TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  {
    echo "## What's new"
    echo
    if [[ -n "$PREVIOUS_TAG" ]]; then
      git -C "$ROOT_DIR" log --no-merges --format='- %s' "$PREVIOUS_TAG..HEAD"
    else
      echo "- First release."
    fi
  } >"$NOTES"
fi
{
  echo
  echo "## Install"
  echo
  echo "Open $DOWNLOAD_NAME and drag Notchy into Applications. To update, quit Notchy first and replace the old copy."
  if [[ "$NOTARIZED" != 1 ]]; then
    echo
    echo "This build is not notarized by Apple. On first launch macOS says it can't verify Notchy: open System Settings → Privacy & Security and click Open Anyway. Notchy asks for its permissions again after each update."
  fi
} >>"$NOTES"

echo "==> Publishing $TAG to $UPDATE_REPOSITORY"
if ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git -C "$ROOT_DIR" tag -a "$TAG" -m "$APP_NAME $VERSION"
fi
git -C "$ROOT_DIR" push origin "$TAG"
mkdir -p "$WORK/upload"
cp "$DMG" "$WORK/upload/$DOWNLOAD_NAME"
gh release create "$TAG" "$WORK/upload/$DOWNLOAD_NAME" --repo "$UPDATE_REPOSITORY" \
  --title "$APP_NAME $VERSION" --notes-file "$NOTES" --latest
echo "==> Published. The website's download link now serves $APP_NAME $VERSION:"
echo "    $DOWNLOAD_LINK"
