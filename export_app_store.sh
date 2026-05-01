#!/bin/zsh
set -e

PROJECT="/Users/vivek-w/Desktop/GhOSt/app-locker/MacShield.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
PBXPROJ_BACKUP="$HOME/Desktop/MacShield-AppStore-project.pbxproj.backup"
SCHEME="MacShield"
TEAM_ID="${APPSTORE_TEAM_ID:-US6HQUFNP6}"
BUNDLE_ID="com.macshield.app"
ARCHIVE="$HOME/Desktop/MacShield-AppStore.xcarchive"
EXPORT_DIR="$HOME/Desktop/MacShield-AppStore-Export"
EXPORT_PLIST="$HOME/Desktop/MacShield-AppStore-ExportOptions.plist"
ENTITLEMENTS="MacShield/Resources/MacShield-AppStore.entitlements"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { echo "\n${YELLOW}▶ $1${NC}"; }
ok() { echo "${GREEN}✔ $1${NC}"; }
fail() { echo "${RED}✘ $1${NC}"; exit 1; }

[ -n "$APPSTORE_KEY_ID" ] || fail "Missing APPSTORE_KEY_ID"
[ -n "$APPSTORE_ISSUER_ID" ] || fail "Missing APPSTORE_ISSUER_ID"
[ -n "$APPSTORE_PRIVATE_KEY_PATH" ] || fail "Missing APPSTORE_PRIVATE_KEY_PATH"
[ -f "$APPSTORE_PRIVATE_KEY_PATH" ] || fail "Private key file not found: $APPSTORE_PRIVATE_KEY_PATH"

restore_project() {
  if [ -f "$PBXPROJ_BACKUP" ]; then
    cp "$PBXPROJ_BACKUP" "$PBXPROJ"
  fi
}
trap restore_project EXIT

step "Cleaning previous App Store build artifacts..."
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$EXPORT_PLIST"
ok "Clean done"

step "Temporarily removing Sparkle from App Store build..."
cp "$PBXPROJ" "$PBXPROJ_BACKUP"
/usr/bin/python3 - "$PBXPROJ" << 'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
for line in [
    "\t\t\t\tA10000000000000000001203 /* Sparkle in Frameworks */,\n",
    "\t\t\t\tA10000000000000000001202 /* Sparkle */,\n",
]:
    text = text.replace(line, "")
path.write_text(text)
PY
ok "Sparkle excluded for this archive only"

step "Writing App Store ExportOptions.plist..."
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF
ok "ExportOptions.plist written"

step "Archiving MacShield for Mac App Store..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APPSTORE_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APPSTORE_KEY_ID" \
  -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="APP_STORE" \
  INFOPLIST_KEY_LSApplicationCategoryType=public.app-category.utilities \
  INFOPLIST_KEY_SUFeedURL= \
  INFOPLIST_KEY_SUPublicEDKey= \
  INFOPLIST_KEY_SUEnableAutomaticChecks=NO \
  | xcpretty 2>/dev/null || true

if [ ! -d "$ARCHIVE" ]; then
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$APPSTORE_PRIVATE_KEY_PATH" \
    -authenticationKeyID "$APPSTORE_KEY_ID" \
    -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="APP_STORE" \
    INFOPLIST_KEY_LSApplicationCategoryType=public.app-category.utilities \
    INFOPLIST_KEY_SUFeedURL= \
    INFOPLIST_KEY_SUPublicEDKey= \
    INFOPLIST_KEY_SUEnableAutomaticChecks=NO
fi

[ -d "$ARCHIVE" ] && ok "Archive created: $ARCHIVE" || fail "Archive failed"

step "Uploading archive to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APPSTORE_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APPSTORE_KEY_ID" \
  -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID"

ok "Upload submitted to App Store Connect"
echo "\nOpen App Store Connect, select the uploaded build after processing, complete compliance/privacy/pricing metadata, then submit for App Review."
