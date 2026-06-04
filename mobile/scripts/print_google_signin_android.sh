#!/usr/bin/env bash
# Print Android package + SHA-1 for Google Sign-In (fixes PlatformException code 10).
set -euo pipefail

PACKAGE="net.bytzgo.app"
KEYSTORE="${ANDROID_SDK_HOME:-$HOME/.android}/debug.keystore"

keytool_cmd() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/keytool" ]]; then
    echo "$JAVA_HOME/bin/keytool"
    return
  fi
  command -v keytool
}

KEYTOOL="$(keytool_cmd 2>/dev/null || true)"
if [[ -z "$KEYTOOL" || ! -x "$KEYTOOL" ]]; then
  echo "keytool not found. Install JDK or set JAVA_HOME." >&2
  exit 1
fi
if [[ ! -f "$KEYSTORE" ]]; then
  echo "Debug keystore not found: $KEYSTORE" >&2
  exit 1
fi

echo ""
echo "BytzGo Google Sign-In (Android)"
echo "================================"
echo "Package name: $PACKAGE"
echo ""
echo "SHA-1 fingerprints (debug keystore — sideload APK uses this unless you use a release keystore):"
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias androiddebugkey -storepass android -keypass android 2>/dev/null \
  | grep -E 'SHA1:|SHA256:' || true
echo ""
echo "Firebase: https://console.firebase.google.com/project/bytzgo-9bd89/settings/general"
echo "  -> Android $PACKAGE -> Add fingerprint -> paste SHA-1 above"
echo ""
echo "serverClientId (Web client, type 3 in google-services.json):"
echo "  645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com"
echo ""
