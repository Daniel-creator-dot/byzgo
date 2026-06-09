#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "  OK   $1"
  else
    echo "  FAIL $1"
    FAIL=1
  fi
}

echo "BytzGo iOS App Store validation"
check "pubspec.yaml" "test -f pubspec.yaml"
check "Runner.xcworkspace" "test -f ios/Runner.xcworkspace/contents.xcworkspacedata"
check "App icon 1024" "test -f ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
check "GoogleService-Info.plist" "test -f ios/Runner/GoogleService-Info.plist"
check "Runner.entitlements" "test -f ios/Runner/Runner.entitlements"
check "Runner.Release.entitlements" "test -f ios/Runner/Runner.Release.entitlements"
check "Sign in with Apple (release)" "grep -q applesignin ios/Runner/Runner.Release.entitlements"
check "Sign in with Apple (debug)" "grep -q applesignin ios/Runner/Runner.entitlements"
check "sign_in_with_apple dependency" "grep -q sign_in_with_apple pubspec.yaml"
check "ExportOptions.plist" "test -f ios/ExportOptions.plist"
check "build_app_store_ipa.sh" "test -x scripts/build_app_store_ipa.sh"
check "Privacy manifest" "test -f ios/Runner/PrivacyInfo.xcprivacy"
check "Export compliance key" "grep -q ITSAppUsesNonExemptEncryption ios/Runner/Info.plist"
check "Google URL scheme" "grep -q CFBundleURLTypes ios/Runner/Info.plist"
check "Firebase bundle ID" "grep -q com.bytzgo.bytzgoMobile ios/Runner/GoogleService-Info.plist"
check "release_defines.json" "test -f release_defines.json"

if command -v curl >/dev/null 2>&1; then
  check "privacy URL" "curl -fsSL -o /dev/null https://www.bytzgo.net/privacy"
  check "terms URL" "curl -fsSL -o /dev/null https://www.bytzgo.net/terms"
fi

if [[ $FAIL -eq 0 ]]; then
  echo "Ready for archive (set Xcode Team + run sync_maps_key for maps)."
else
  exit 1
fi
