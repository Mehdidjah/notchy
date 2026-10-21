#!/usr/bin/env bash
# Builds Assets/AppIcon/AppIcon.icns from Assets/AppIcon/artwork.png. Run it after changing the
# artwork and commit both; script/build_and_run.sh only copies the finished icon.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ICON_DIR="$ROOT_DIR/Assets/AppIcon"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT_DIR/script/app-icon/make-icon.swift" "$ICON_DIR/artwork.png" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_DIR/AppIcon.icns"
echo "$ICON_DIR/AppIcon.icns"
