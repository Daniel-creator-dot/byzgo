#!/bin/bash
# Double-click on Mac: fresh iOS Simulator build (includes latest pricing fixes).
set -e
cd "$(dirname "$0")"
MOBILE="$(pwd)"

echo "=========================================="
echo "  BytzGo — iOS Simulator build (1.0.13+)"
echo "=========================================="
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This file only works on a Mac with Xcode."
  read -r -p "Press Enter to close..."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Install: brew install --cask flutter"
  read -r -p "Press Enter to close..."
  exit 1
fi

if [[ ! -f dart_defines.json ]]; then
  cp dart_defines.json.example dart_defines.json
  echo "Created dart_defines.json (production API by default)."
fi

echo "→ Cleaning stale Flutter iOS config (fixes Xcode exit 127)"
rm -f ios/Flutter/Generated.xcconfig ios/Flutter/flutter_export_environment.sh 2>/dev/null || true

echo "→ flutter pub get"
flutter pub get

if command -v pod >/dev/null 2>&1; then
  echo "→ pod install"
  (cd ios && pod install)
else
  echo "→ Skipping pod install (brew install cocoapods)"
fi

echo "→ Opening Simulator"
open -a Simulator 2>/dev/null || true

echo "→ Building for iOS Simulator..."
flutter build ios --simulator \
  --dart-define-from-file=dart_defines.json

echo "→ Installing and running on simulator..."
flutter run -d ios \
  --dart-define-from-file=dart_defines.json

echo ""
echo "Done. App should be running on the iPhone Simulator."
read -r -p "Press Enter to close..."
