#!/usr/bin/env bash
# One-shot iOS/Xcode setup for BytzGo (run on macOS with Xcode installed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS (Xcode + CocoaPods)." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Install: https://docs.flutter.dev/get-started/install/macos" >&2
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods not found. Install: sudo gem install cocoapods  OR  brew install cocoapods" >&2
  exit 1
fi

if [[ ! -f dart_defines.json ]]; then
  cp dart_defines.json.example dart_defines.json
  echo "Created dart_defines.json from example (edit API_URL if needed)."
fi

echo "→ flutter pub get"
flutter pub get

echo "→ pod install"
(cd ios && pod install)

WORKSPACE="$ROOT/ios/Runner.xcworkspace"
echo "→ Opening Xcode: $WORKSPACE"
open "$WORKSPACE"

echo ""
echo "Done. In Xcode: select an iPhone simulator, then press Run (⌘R)."
echo "Or run: flutter run -d ios --dart-define-from-file=dart_defines.json"
