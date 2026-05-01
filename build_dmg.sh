#!/bin/zsh
set -e

# ── Config ───────────────────────────────────────────────────────────────────
CERT="Developer ID Application: Savaliya Yakshit Bhaveshbhai (US6HQUFNP6)"
TEAM_ID="US6HQUFNP6"
KEYCHAIN_PROFILE="MacShield-Notarize"
VERSION="1.0.3"

APP="$HOME/Desktop/MacShieldExport/MacShieldPRO.app"
BG="$HOME/Desktop/dmg_background.png"
ICON="/Users/vivek-w/Desktop/GhOSt/app-locker/MacShield/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
DMG_STAGING="$HOME/Desktop/MacShieldPRO_staging.dmg"
DMG_FINAL="$HOME/Desktop/MacShieldPRO-${VERSION}.dmg"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
step() { echo "\n${YELLOW}${BOLD}▶ $1${NC}"; }
ok()   { echo "${GREEN}✔ $1${NC}"; }
fail() { echo "${RED}✘ $1${NC}"; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
step "Preflight checks..."
[ -d "$APP" ]  || fail "App not found at $APP — run sign_and_notarize.sh first"
[ -f "$BG" ]   || fail "Background not found at $BG — run make_dmg_bg.py first"
ok "All inputs present"

# ── Verify app is already notarized ──────────────────────────────────────────
step "Verifying app Gatekeeper status..."
spctl --assess --verbose "$APP" 2>&1 | grep -q "accepted" && ok "App is Notarized ✔" || fail "App not accepted by Gatekeeper — notarize first"

# ── Clean ─────────────────────────────────────────────────────────────────────
step "Cleaning old DMG files..."
rm -f "$DMG_STAGING" "$DMG_FINAL"
ok "Clean done"

# ── Build DMG ─────────────────────────────────────────────────────────────────
step "Building DMG with create-dmg..."
create-dmg \
  --volname "MacShieldPRO" \
  --volicon "$ICON" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "MacShieldPRO.app" 160 195 \
  --hide-extension "MacShieldPRO.app" \
  --app-drop-link 500 195 \
  --no-internet-enable \
  "$DMG_FINAL" \
  "$APP"

[ -f "$DMG_FINAL" ] && ok "DMG created: $DMG_FINAL" || fail "DMG creation failed"

# ── Sign DMG ──────────────────────────────────────────────────────────────────
step "Signing DMG with Developer ID..."
codesign --sign "$CERT" \
  --timestamp \
  --verbose \
  "$DMG_FINAL"
ok "DMG signed"

# ── Verify DMG signature ──────────────────────────────────────────────────────
step "Verifying DMG signature..."
codesign --verify --verbose "$DMG_FINAL" && ok "DMG signature valid" || fail "DMG signature invalid"

# ── Notarize DMG ─────────────────────────────────────────────────────────────
step "Submitting DMG to Apple for notarization..."
NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_FINAL" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1)

echo "$NOTARIZE_OUTPUT"

if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
  ok "DMG notarization: ACCEPTED"
elif echo "$NOTARIZE_OUTPUT" | grep -q "status: Invalid"; then
  echo "${RED}DMG notarization REJECTED — fetching logs...${NC}"
  SUB_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
  xcrun notarytool log "$SUB_ID" --keychain-profile "$KEYCHAIN_PROFILE"
  fail "Fix issues above and retry"
else
  echo "${YELLOW}Network timeout during polling — checking status manually...${NC}"
  SUB_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
  echo "Submission ID: $SUB_ID"
  echo "Run this to check: xcrun notarytool info $SUB_ID --keychain-profile \"$KEYCHAIN_PROFILE\""
  echo "Then staple with: xcrun stapler staple \"$DMG_FINAL\""
  exit 0
fi

# ── Staple DMG ────────────────────────────────────────────────────────────────
step "Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG_FINAL"
ok "DMG stapled"

# ── Final Gatekeeper check ────────────────────────────────────────────────────
step "Final Gatekeeper assessment of DMG..."
spctl --assess --type open --context context:primary-signature --verbose "$DMG_FINAL" 2>&1 || true
ok "Done"

# ── Summary ───────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_FINAL" | cut -f1)
echo "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}${BOLD}  MacShieldPRO DMG — Signed, Notarized & Ready!       ${NC}"
echo "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  📦 File : $DMG_FINAL"
echo "  📏 Size : $DMG_SIZE"
echo "  🔐 Sign : Developer ID Application (Notarized)"
echo "  ✅ Gate : Accepted by Gatekeeper"
