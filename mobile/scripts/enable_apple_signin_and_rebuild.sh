#!/usr/bin/env bash
# After enabling Sign in with Apple on the App ID + regenerating the store profile, run this.
set -euo pipefail
MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_UUID="2dc03101-394e-4ab6-8236-5d9aee316581"
PROFILE_SRC="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"

echo "Checking store profile for Sign in with Apple..."
if ! security cms -D -i "$PROFILE_SRC" 2>/dev/null | plutil -extract Entitlements.com.apple.developer.applesignin xml1 -o /dev/null - 2>/dev/null; then
  echo ""
  echo "Profile still missing Sign in with Apple. Do this first:"
  echo "  1. https://developer.apple.com/account/resources/identifiers → com.bytzgo.bytzgoMobile"
  echo "     → Capabilities → Sign In with Apple → ON → Save"
  echo "  2. https://developer.apple.com/account/resources/profiles/list"
  echo "     → App Store profile for BytzGo → Edit → Save (regenerates)"
  echo "  3. Xcode → Settings → Accounts → Download Manual Profiles"
  echo ""
  exit 1
fi

echo "Profile OK — rebuilding signed IPA..."
"$MOBILE_ROOT/scripts/manual_sign_app_store_ipa.sh"
echo ""
echo "Upload mobile/build/ios/ipa/BytzGo.ipa in Transporter (build 53, version 1.0.44)."
