#!/bin/bash
# Double-click this file in Finder (Mac only) to set up and open BytzGo in Xcode.
set -e
cd "$(dirname "$0")"
MOBILE="$(pwd)"

echo "=========================================="
echo "  BytzGo — open in Xcode (simulator)"
echo "=========================================="
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This file only works on a Mac."
  read -r -p "Press Enter to close..."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed yet."
  echo ""
  echo "Do this ONCE:"
  echo "  1. Install Homebrew: https://brew.sh"
  echo "  2. In Terminal, run:  brew install --cask flutter"
  echo "  3. Double-click this file again"
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

echo "→ flutter pub get"
rm -f ios/Flutter/Generated.xcconfig ios/Flutter/flutter_export_environment.sh 2>/dev/null || true
flutter pub get

GEN="ios/Flutter/Generated.xcconfig"
if [[ ! -f "$GEN" ]]; then
  echo "ERROR: Could not create $GEN"
  read -r -p "Press Enter to close..."
  exit 1
fi
echo "   $(grep '^FLUTTER_ROOT=' "$GEN")"

if command -v pod >/dev/null 2>&1; then
  echo "→ pod install"
  (cd ios && pod install)
else
  echo "→ Skipping pod install (install with: brew install cocoapods)"
fi

echo "→ Opening Xcode..."
open ios/Runner.xcworkspace

echo ""
echo "In Xcode:"
echo "  1. Top bar: choose iPhone simulator (e.g. iPhone 17)"
echo "  2. Press the Play button (or Command+R)"
echo ""
read -r -p "Press Enter to close this window..."
