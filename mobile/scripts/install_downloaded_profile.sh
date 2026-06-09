#!/usr/bin/env bash
# Install the newest BytzGo App Store profile from ~/Downloads and verify Apple Sign In.
set -euo pipefail
DEST="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
MOBILE_DEST="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$DEST" "$MOBILE_DEST"

latest="$(ls -t "$HOME/Downloads"/*.mobileprovision 2>/dev/null | head -1 || true)"
if [[ -z "$latest" ]]; then
  echo "No .mobileprovision in ~/Downloads. Download the profile from developer.apple.com first."
  exit 1
fi

name="$(security cms -D -i "$latest" | plutil -extract Name xml1 -o - - 2>/dev/null | sed 's/.*<string>//;s/<\/string>.*//')"
bundle="$(security cms -D -i "$latest" | plutil -extract Entitlements.application-identifier xml1 -o - - 2>/dev/null | sed 's/.*<string>//;s/<\/string>.*//')"
uuid="$(security cms -D -i "$latest" | plutil -extract UUID xml1 -o - - 2>/dev/null | sed 's/.*<string>//;s/<\/string>.*//')"

echo "Found: $name"
echo "Bundle: $bundle"
echo "UUID: $uuid"

if [[ "$bundle" != *"com.bytzgo.bytzgoMobile" ]]; then
  echo "This profile is not for com.bytzgo.bytzgoMobile — download the BytzGo App Store profile."
  exit 1
fi

if ! security cms -D -i "$latest" | plutil -extract Entitlements.com.apple.developer.applesignin xml1 -o /dev/null - 2>/dev/null; then
  echo "Profile still missing Sign in with Apple — Save the profile again on developer.apple.com."
  exit 1
fi

cp "$latest" "$DEST/${uuid}.mobileprovision"
cp "$latest" "$MOBILE_DEST/${uuid}.mobileprovision"
echo "Installed to $DEST/${uuid}.mobileprovision"
echo "Update PROFILE_UUID in manual_sign_app_store_ipa.sh if it changed: $uuid"
