#!/usr/bin/env bash
# Upload BytzGo.ipa to App Store Connect via iTMSTransporter.
#
# Requires an app-specific password (not your Apple ID password):
#   https://account.apple.com → Sign-In and Security → App-Specific Passwords
#
# Usage:
#   export APPLE_ID="you@example.com"
#   export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ./scripts/upload_app_store_ipa.sh
#
# Or add APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD to repo-root .env.local (gitignored).
set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${IPA:-$MOBILE_ROOT/build/ios/ipa/BytzGo.ipa}"
REPO_ROOT="$(cd "$MOBILE_ROOT/.." && pwd)"

read_env() {
  local name="$1" file="$REPO_ROOT/.env.local"
  [[ -f "$file" ]] || return 0
  grep -E "^\s*${name}\s*=" "$file" 2>/dev/null | head -1 | sed -E "s/^\s*${name}\s*=\s*//" | tr -d "\"'" | sed 's/[[:space:]]*$//'
}

APPLE_ID="${APPLE_ID:-$(read_env APPLE_ID)}"
APPLE_ID="${APPLE_ID:-jerryanthony61@gmail.com}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-$(read_env APPLE_APP_SPECIFIC_PASSWORD)}"

[[ -f "$IPA" ]] || { echo "Missing IPA: $IPA — run manual_sign_app_store_ipa.sh first"; exit 1; }
[[ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]] || {
  echo "Set APPLE_APP_SPECIFIC_PASSWORD (app-specific password from account.apple.com)."
  echo "Then: APPLE_ID=$APPLE_ID APPLE_APP_SPECIFIC_PASSWORD=**** ./scripts/upload_app_store_ipa.sh"
  exit 1
}

TRANSPORTER="/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter"
[[ -x "$TRANSPORTER" ]] || { echo "Install Transporter from the Mac App Store."; exit 1; }

echo "→ Validating $IPA"
xcrun altool --validate-app -f "$IPA" -t ios -u "$APPLE_ID" -p "$APPLE_APP_SPECIFIC_PASSWORD" 2>&1 | tail -15

echo "→ Uploading to App Store Connect"
"$TRANSPORTER" -m upload -assetFile "$IPA" -u "$APPLE_ID" -p "$APPLE_APP_SPECIFIC_PASSWORD" 2>&1 | tail -20

echo ""
echo "Done. In App Store Connect, attach build $(grep '^version:' "$MOBILE_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d+ -f2) to marketing version $(grep '^version:' "$MOBILE_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)."
