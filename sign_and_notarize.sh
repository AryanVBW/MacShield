#!/bin/zsh
set -e

# ── Config ──────────────────────────────────────────────────────────────────
PROJECT="/Users/vivek-w/Desktop/GhOSt/app-locker/MacShield.xcodeproj"
SCHEME="MacShield"
CERT="Developer ID Application: Savaliya Yakshit Bhaveshbhai (US6HQUFNP6)"
TEAM_ID="US6HQUFNP6"
KEYCHAIN_PROFILE="MacShield-Notarize"
BUNDLE_ID="com.macshield.app"

ARCHIVE="$HOME/Desktop/MacShield.xcarchive"
EXPORT_DIR="$HOME/Desktop/MacShieldExport"
EXPORT_PLIST="$HOME/Desktop/MacShieldExportOptions.plist"
APP="$EXPORT_DIR/MacShieldPRO.app"
ZIP="$HOME/Desktop/MacShield_notarize.zip"
FINAL_APP="$HOME/Desktop/MacShieldPRO_signed.app"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { echo "\n${YELLOW}▶ $1${NC}"; }
ok()   { echo "${GREEN}✔ $1${NC}"; }
fail() { echo "${RED}✘ $1${NC}"; exit 1; }

# ── Clean previous output ────────────────────────────────────────────────────
step "Cleaning previous build artifacts..."
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$ZIP" "$EXPORT_PLIST" "$FINAL_APP"
ok "Clean done"

# ── Write ExportOptions.plist ────────────────────────────────────────────────
step "Writing ExportOptions.plist..."
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>hardcodedEmbeddedProvision</key>
    <false/>
</dict>
</plist>
EOF
ok "ExportOptions.plist written"

# ── Archive ──────────────────────────────────────────────────────────────────
step "Archiving MacShield (this may take a minute)..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CERT" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  | xcpretty 2>/dev/null || true

# Fallback if xcpretty not installed
if [ ! -d "$ARCHIVE" ]; then
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$CERT" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PROVISIONING_PROFILE_SPECIFIER=""
fi

[ -d "$ARCHIVE" ] && ok "Archive created: $ARCHIVE" || fail "Archive failed"

# ── Export ───────────────────────────────────────────────────────────────────
step "Exporting signed .app..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

[ -d "$APP" ] && ok "Exported: $APP" || fail "Export failed"

# ── Verify signature before notarizing ───────────────────────────────────────
step "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP" && ok "Signature OK" || fail "Signature invalid"

# ── Zip for notarization ─────────────────────────────────────────────────────
step "Creating ZIP for notarization..."
ditto -c -k --keepParent "$APP" "$ZIP"
ok "ZIP created: $ZIP"

# ── Notarize ─────────────────────────────────────────────────────────────────
step "Submitting to Apple for notarization (waiting for result)..."
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

ok "Notarization complete"

# ── Staple ───────────────────────────────────────────────────────────────────
step "Stapling notarization ticket to app..."
xcrun stapler staple "$APP"
ok "Stapled"

# ── Copy final app to Desktop ─────────────────────────────────────────────────
step "Copying final app to Desktop..."
cp -R "$APP" "$FINAL_APP"
ok "Final app: $FINAL_APP"

# ── Final Gatekeeper check ────────────────────────────────────────────────────
step "Gatekeeper assessment..."
spctl --assess --verbose "$FINAL_APP" && ok "Gatekeeper: ACCEPTED ✔" || fail "Gatekeeper rejected"

echo "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}  MacShield is signed, notarized & ready to ship!  ${NC}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  📦 App: $FINAL_APP"
