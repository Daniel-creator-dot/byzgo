#!/usr/bin/env bash
# One-time setup after cloning BytzGo — prepares Android Studio / Flutter (Linux/macOS).
# Run from repo root: bash mobile/scripts/setup_android_studio.sh
set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$MOBILE_ROOT/.." && pwd)"
cd "$MOBILE_ROOT"

find_flutter_sdk() {
  if command -v flutter >/dev/null 2>&1; then
    dirname "$(dirname "$(command -v flutter)")"
    return
  fi
  for c in "$REPO_ROOT/.flutter-sdk" "$HOME/flutter" "$HOME/develop/flutter"; do
    if [[ -x "$c/bin/flutter" ]]; then
      echo "$c"
      return
    fi
  done
  return 1
}

find_android_sdk() {
  for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [[ -n "$c" && -d "$c" ]]; then
      echo "$c"
      return
    fi
  done
  return 1
}

echo ""
echo "BytzGo — Android Studio setup"
echo "============================="
echo ""

FLUTTER_SDK="$(find_flutter_sdk)" || {
  echo "Flutter SDK not found. Install from https://docs.flutter.dev/get-started/install"
  exit 1
}

ANDROID_SDK="$(find_android_sdk)" || {
  echo "Android SDK not found. Install via Android Studio → SDK Manager."
  exit 1
}

echo "Flutter SDK : $FLUTTER_SDK"
echo "Android SDK : $ANDROID_SDK"
echo ""

LOCAL_PROPS="$MOBILE_ROOT/android/local.properties"
MAPS_KEY=""
ENV_LOCAL="$REPO_ROOT/.env.local"
if [[ -f "$ENV_LOCAL" ]]; then
  MAPS_KEY="$(grep -E '^\s*(GOOGLE_MAPS_API_KEY|VITE_GOOGLE_MAPS_API_KEY)\s*=' "$ENV_LOCAL" | head -1 | sed -E "s/^\s*[^=]+=\s*//" | tr -d "\"'" | sed 's/[[:space:]]*$//')"
fi

{
  echo "flutter.sdk=$FLUTTER_SDK"
  echo "sdk.dir=$ANDROID_SDK"
  [[ -n "$MAPS_KEY" ]] && echo "GOOGLE_MAPS_API_KEY=$MAPS_KEY"
} > "$LOCAL_PROPS"
echo "Wrote android/local.properties"

if [[ ! -f "$MOBILE_ROOT/dart_defines.json" ]]; then
  cp "$MOBILE_ROOT/dart_defines.json.example" "$MOBILE_ROOT/dart_defines.json"
  echo "Created dart_defines.json from example"
else
  echo "dart_defines.json already exists — kept"
fi

if [[ -f "$MOBILE_ROOT/scripts/sync_maps_key.mjs" ]] && command -v node >/dev/null 2>&1; then
  echo ""
  echo "Syncing Maps key..."
  node "$MOBILE_ROOT/scripts/sync_maps_key.mjs" || true
fi

echo ""
echo "Running flutter pub get..."
"$FLUTTER_SDK/bin/flutter" pub get

echo ""
"$FLUTTER_SDK/bin/flutter" doctor

echo ""
echo "Setup complete."
echo ""
echo "Android Studio:"
echo "  1. File → Open → select folder: $MOBILE_ROOT"
echo "  2. Device Manager → Play on a virtual device"
echo "  3. Run config: BytzGo (production)"
echo ""
echo "Terminal: cd $REPO_ROOT && npm run flutter:android"
echo ""
