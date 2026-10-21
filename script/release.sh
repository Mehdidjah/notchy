#!/usr/bin/env bash
# Packages Notchy into a disk image other Macs can install from, and optionally publishes it as
# a release that installed copies find through their update check.
#
#   script/release.sh            build dist/release/Notchy-<version>.dmg
#   script/release.sh --publish  also tag v<version> and upload the image as a GitHub release
#
# The version comes from VERSION; raise it before each release. Environment:
#   UPDATE_REPOSITORY  public owner/name the app checks and --publish uploads to
#                      (default Mehdidjah/notchy-releases)
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
  git -C "$ROOT_DIR" diff --quiet && git -C "$ROOT_DIR" diff --cached --quiet \
    || fail "commit your changes first; a release is built from a committed tree"
  if gh release view "$TAG" --repo "$UPDATE_REPOSITORY" >/dev/null 2>&1; then
    fail "$TAG is already published in $UPDATE_REPOSITORY; raise VERSION"
  fi
fi

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
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# The mounted image wears the app icon. Marking the volume as having a custom icon takes
# SetFile, which comes with Xcode; without it the image just has the standard disk icon.
cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
READ_WRITE="$(mktemp -d)/$APP_NAME.dmg"
MOUNT="$(mktemp -d)"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$READ_WRITE" >/dev/null
hdiutil attach "$READ_WRITE" -nobrowse -noautoopen -mountpoint "$MOUNT" >/dev/null
if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "$MOUNT"
else
  echo "warning: SetFile not found (it comes with Xcode); the disk image keeps the standard icon" >&2
fi
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$READ_WRITE" -format UDZO -ov -o "$DMG" >/dev/null
rm -rf "$(dirname "$READ_WRITE")" "$MOUNT"

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

NOTES="$STAGING/notes.md"
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
  echo "Open $(basename "$DMG") and drag Notchy into Applications. To update, quit Notchy first and replace the old copy."
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
gh release create "$TAG" "$DMG" --repo "$UPDATE_REPOSITORY" --title "$APP_NAME $VERSION" --notes-file "$NOTES"
