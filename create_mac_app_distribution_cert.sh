#!/bin/bash
set -euo pipefail

export APPSTORE_KEY_ID="2454HV52M5"
export APPSTORE_ISSUER_ID="d2a601f6-c419-4673-aaf3-585ff9332212"
export APPSTORE_PRIVATE_KEY_PATH="/Users/vivek-w/AuthKey_2454HV52M5.p8"
export APPSTORE_TEAM_ID="US6HQUFNP6"

WORKDIR="$HOME/.appstoreconnect/certificates/mac_app_distribution_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WORKDIR"
chmod 700 "$HOME/.appstoreconnect" "$HOME/.appstoreconnect/certificates" "$WORKDIR"

echo "WORKDIR=$WORKDIR"
openssl genrsa -out "$WORKDIR/MacAppDistribution.key" 2048
openssl req -new \
  -key "$WORKDIR/MacAppDistribution.key" \
  -out "$WORKDIR/MacAppDistribution.csr" \
  -subj "/emailAddress=developer@macshield.local,CN=Mac App Distribution,OU=$APPSTORE_TEAM_ID,O=MacShield,C=US"

python3 /Users/vivek-w/Desktop/GhOSt/app-locker/create_mac_app_distribution_cert.py "$WORKDIR"

openssl pkcs12 -export \
  -inkey "$WORKDIR/MacAppDistribution.key" \
  -in "$WORKDIR/MacAppDistribution.cer.pem" \
  -out "$WORKDIR/MacAppDistribution.p12" \
  -passout pass:

security import "$WORKDIR/MacAppDistribution.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "" \
  -A

security find-identity -v -p codesigning | egrep 'Mac App Distribution|Apple Distribution|3rd Party Mac Developer|Developer ID Application|valid identities'
echo "Saved certificate materials in: $WORKDIR"
