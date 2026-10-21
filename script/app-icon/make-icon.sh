#!/usr/bin/env bash
# Makes Notchy's icons from Assets/AppIcon/artwork.png: the layers of the Liquid Glass icon
# (Assets/AppIcon/AppIcon.icon, whose icon.json says how they are stacked and lit) and the flat
# AppIcon.icns for macOS before 26. Run it after changing the artwork and commit the results;
# script/build_and_run.sh compiles the glass icon and copies the flat one.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ICON_DIR="$ROOT_DIR/Assets/AppIcon"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT_DIR/script/app-icon/make-layers.swift" "$ICON_DIR/artwork.png" "$ICON_DIR/AppIcon.icon/Assets"
swift "$ROOT_DIR/script/app-icon/make-icon.swift" "$ICON_DIR/artwork.png" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_DIR/AppIcon.icns"
echo "$ICON_DIR/AppIcon.icon"
echo "$ICON_DIR/AppIcon.icns"
