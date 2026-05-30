#!/usr/bin/env bash
# Build Resources/branding/AppIcon.icns from a 1024x1024 PNG source.
# Re-run any time you swap the source PNG.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/Resources/branding/tapir-icon-v2.png}"
OUT="$ROOT/Resources/branding/AppIcon.icns"
STAGE="$(mktemp -d)/AppIcon.iconset"

if [[ ! -f "$SRC" ]]; then
  echo "Source PNG not found: $SRC"
  exit 1
fi

mkdir -p "$STAGE"

# Apple-required iconset sizes
sips -z   16   16 "$SRC" --out "$STAGE/icon_16x16.png"       >/dev/null
sips -z   32   32 "$SRC" --out "$STAGE/icon_16x16@2x.png"    >/dev/null
sips -z   32   32 "$SRC" --out "$STAGE/icon_32x32.png"       >/dev/null
sips -z   64   64 "$SRC" --out "$STAGE/icon_32x32@2x.png"    >/dev/null
sips -z  128  128 "$SRC" --out "$STAGE/icon_128x128.png"     >/dev/null
sips -z  256  256 "$SRC" --out "$STAGE/icon_128x128@2x.png"  >/dev/null
sips -z  256  256 "$SRC" --out "$STAGE/icon_256x256.png"     >/dev/null
sips -z  512  512 "$SRC" --out "$STAGE/icon_256x256@2x.png"  >/dev/null
sips -z  512  512 "$SRC" --out "$STAGE/icon_512x512.png"     >/dev/null
cp "$SRC"               "$STAGE/icon_512x512@2x.png"

iconutil -c icns "$STAGE" -o "$OUT"

echo "✓ Wrote $OUT ($(wc -c < "$OUT") bytes) from $(basename "$SRC")"
