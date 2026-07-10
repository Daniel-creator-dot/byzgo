#!/usr/bin/env bash
# Build unsigned release, sign with local Distribution cert + store profile, zip IPA.
# Use when flutter build ipa fails (no Apple ID in Xcode) but keychain + profiles exist.
set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$MOBILE_ROOT/build/ios/iphoneos/Runner.app"
ENT="$MOBILE_ROOT/ios/Runner/Runner.Release.entitlements"
ENT_TMP="$(mktemp)"
profile_field() {
  local file="$1" key="$2"
  security cms -D -i "$file" 2>/dev/null | plutil -extract "$key" raw -o - - 2>/dev/null || true
}

find_store_profile() {
  local dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  local f uuid bundle
  # Prefer newest matching profile (handles regenerated App Store profiles).
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    bundle="$(profile_field "$f" Entitlements.application-identifier)"
    [[ "$bundle" == *"com.bytzgo.bytzgoMobile" ]] || continue
    security cms -D -i "$f" 2>/dev/null | grep -q 'com.apple.developer.applesignin' || continue
    uuid="$(profile_field "$f" UUID)"
    [[ -n "$uuid" ]] || continue
    echo "$uuid|$f"
    return 0
  done < <(ls -t "$dir"/*.mobileprovision 2>/dev/null)
  return 1
}

PROFILE_PAIR="$(find_store_profile || true)"
if [[ -z "$PROFILE_PAIR" ]]; then
  echo "No App Store profile for com.bytzgo.bytzgoMobile found."
  echo "Download from developer.apple.com → Profiles → BytzGo App Store → Download"
  echo "Then: ./scripts/install_downloaded_profile.sh"
  exit 1
fi
PROFILE_UUID="${PROFILE_PAIR%%|*}"
PROFILE_SRC="${PROFILE_PAIR#*|}"
echo "Using profile $PROFILE_UUID"
IDENTITY="Apple Distribution: jeremiah anthony amissah (MHTN5HYAHW)"
IPA_DIR="$MOBILE_ROOT/build/ios/ipa"
trap 'rm -f "$ENT_TMP"' EXIT

pod_cmd() {
  local vendor_pod="$MOBILE_ROOT/ios/vendor/bundle/ruby/2.6.0/bin/pod"
  if [[ -x "$vendor_pod" ]]; then
    export GEM_HOME="$MOBILE_ROOT/ios/vendor/bundle/ruby/2.6.0"
    export GEM_PATH="$GEM_HOME"
    export PATH="$GEM_HOME/bin:$PATH"
    POD_BIN="$vendor_pod"
  else
    POD_BIN="pod"
  fi
}

flutter_cmd() {
  if [[ -x /Users/macbookpro/development/flutter/bin/flutter ]]; then
    echo /Users/macbookpro/development/flutter/bin/flutter
  else
    echo flutter
  fi
}

pod_cmd
FLUTTER="$(flutter_cmd)"
export PATH="$MOBILE_ROOT/ios/vendor/bundle/ruby/2.6.0/bin:${PATH:-}"
(cd "$MOBILE_ROOT/ios" && "$POD_BIN" install)
(cd "$MOBILE_ROOT/ios" && xcodebuild -resolvePackageDependencies -workspace Runner.xcworkspace -scheme Runner >/dev/null)
"$FLUTTER" build ios --release --no-codesign --dart-define-from-file="$MOBILE_ROOT/dart_defines.json"

[[ -f "$PROFILE_SRC" ]] || { echo "Missing profile: $PROFILE_SRC"; exit 1; }
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_SRC" "$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
cp "$PROFILE_SRC" "$APP/embedded.mobileprovision"

# Entitlements must match the provisioning profile (incl. application-identifier).
security cms -D -i "$PROFILE_SRC" | plutil -extract Entitlements xml1 -o "$ENT_TMP" -
if ! grep -q 'com.apple.developer.applesignin' "$ENT_TMP" 2>/dev/null; then
  echo "WARNING: Store profile lacks Sign in with Apple."
  echo "  1. developer.apple.com → Identifiers → com.bytzgo.bytzgoMobile → enable Sign In with Apple → Save"
  echo "  2. Profiles → App Store profile → Edit → Save (regenerate) → Xcode downloads it"
  echo "  3. Re-run this script. IPA may fail App Review for Apple login until then."
fi
# Sign with provisioning-profile entitlements only (never merge Runner.Release.entitlements —
# extra keys like time-sensitive break App Store Connect validation).

sign_item() {
  local target="$1"
  if [[ -e "$target" ]]; then
    /usr/bin/codesign --force --sign "$IDENTITY" --preserve-metadata=identifier,entitlements,flags --timestamp=none "$target" 2>/dev/null || \
    /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$target"
  fi
}

while IFS= read -r -d '' item; do sign_item "$item"; done < <(find "$APP" \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -print0 | sort -rz)
/usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$ENT_TMP" --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

mkdir -p "$IPA_DIR/Payload"
rm -rf "$IPA_DIR/Payload/Runner.app"
cp -R "$APP" "$IPA_DIR/Payload/"
(cd "$IPA_DIR" && rm -f BytzGo.ipa && zip -qr BytzGo.ipa Payload)

echo "IPA: $IPA_DIR/BytzGo.ipa"
if [[ -d /Applications/Transporter.app ]]; then
  open -a Transporter "$IPA_DIR/BytzGo.ipa" 2>/dev/null || true
fi
