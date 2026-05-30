#!/usr/bin/env bash
# Create a stable self-signed code-signing identity for ClickInsight dev builds.
#
# Why: ad-hoc signing (`codesign -s -`) changes the binary's code identity on
# every rebuild, so TCC (Accessibility / Screen Recording) treats each build
# as a new app and re-prompts. A stable identity lets TCC remember the grant
# across rebuilds.
#
# Run this ONCE. Future `bash scripts/make-app.sh` will detect and use it.

set -euo pipefail

IDENTITY_NAME="ClickInsight Local Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "✓ Identity '$IDENTITY_NAME' already installed. Nothing to do."
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl not found. Install Xcode CLT or Homebrew openssl."
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

cat > cert.cnf <<EOF
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = req_ext

[req_dn]
CN = $IDENTITY_NAME
O = ClickInsight Local

[req_ext]
extendedKeyUsage = codeSigning
basicConstraints = CA:false
EOF

echo "==> Generating RSA 2048 key + self-signed cert (10y)"
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout key.pem -out cert.pem \
  -config cert.cnf 2>/dev/null

PASS="clickinsight-dev"

openssl pkcs12 -export -inkey key.pem -in cert.pem \
  -out identity.p12 -name "$IDENTITY_NAME" \
  -passout "pass:$PASS" 2>/dev/null

echo "==> Importing into login keychain"
echo "    (macOS may ask for your login password to unlock the keychain)"
security import identity.p12 \
  -k "$KEYCHAIN" \
  -P "$PASS" \
  -A >/dev/null

cd - >/dev/null

echo ""
echo "✓ Identity installed: $IDENTITY_NAME"
echo ""
echo "  Next:"
echo "    1. bash scripts/make-app.sh"
echo "    2. macOS will ask permission for codesign to access the key — click 'Always Allow'"
echo "    3. Launch the app, grant Accessibility / Screen Recording once"
echo "    4. All future rebuilds will reuse the same TCC authorization"
