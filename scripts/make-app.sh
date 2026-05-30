#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
BUNDLE_ID="app.clickinsight.local"
IDENTITY_NAME="ClickInsight Local Dev"
PRODUCT="Tapir"

echo "==> swift build (-c $CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
EXE="$BIN_PATH/$PRODUCT"

if [[ ! -f "$EXE" ]]; then
  echo "Build artifact not found at $EXE"
  exit 1
fi

APP_DIR="$ROOT/$PRODUCT.app"
echo "==> Assembling $APP_DIR"
# Drop any previous bundle (incl. the legacy ClickInsight.app from before the rename)
rm -rf "$APP_DIR" "$ROOT/ClickInsight.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$EXE" "$APP_DIR/Contents/MacOS/$PRODUCT"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

ICON_SRC="$ROOT/Resources/branding/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "  (skip icon: $ICON_SRC missing — run scripts/make-icon.sh first)"
fi

# Pick signing identity
if security find-identity -p codesigning -v 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  IDENTITY_TO_USE="$IDENTITY_NAME"
  USE_STABLE=true
else
  IDENTITY_TO_USE="-"
  USE_STABLE=false
fi

# Auto-reset TCC when the signing identity has changed (e.g. switching
# from ad-hoc to stable, or first-time setup). When the same stable
# identity is reused, TCC entries stay valid and we skip the reset.
STATE_DIR="$ROOT/.build/clickinsight-meta"
STATE_FILE="$STATE_DIR/last_signing_identity"
mkdir -p "$STATE_DIR"

PREV_IDENTITY=""
[[ -f "$STATE_FILE" ]] && PREV_IDENTITY="$(cat "$STATE_FILE")"

RESET_TCC=false
if [[ "$USE_STABLE" != "true" ]]; then
  # Ad-hoc cdhash changes on every rebuild; clear stale entries each time.
  RESET_TCC=true
elif [[ "$PREV_IDENTITY" != "$IDENTITY_TO_USE" ]]; then
  RESET_TCC=true
fi

if [[ "$RESET_TCC" == "true" ]]; then
  echo "==> Resetting TCC entries for $BUNDLE_ID (signing identity changed)"
  # Kill running instance so the new launch is a clean re-grant
  pkill -f "$PRODUCT.app/Contents/MacOS" 2>/dev/null || true
  pkill -f "ClickInsight.app/Contents/MacOS" 2>/dev/null || true
  tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
fi

echo "$IDENTITY_TO_USE" > "$STATE_FILE"

if [[ "$USE_STABLE" == "true" ]]; then
  echo "==> Codesigning with stable identity: $IDENTITY_NAME"
  codesign --force --deep --options runtime --sign "$IDENTITY_NAME" "$APP_DIR"
else
  echo "==> Codesigning ad-hoc"
  echo "    Run \`bash scripts/setup-identity.sh\` once for persistent TCC grants."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo ""
echo "Done. Launch with:"
echo "  open '$APP_DIR'"
if [[ "$RESET_TCC" == "true" ]]; then
  echo ""
  echo "TCC was reset — macOS will prompt again for Accessibility on launch."
fi
