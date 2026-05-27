#!/usr/bin/env bash
# Build release IPA for TestFlight / App Store (macOS + Xcode required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -x "$(command -v node)" ]] && [[ -f "$ROOT/scripts/sync_maps_key.mjs" ]]; then
  node "$ROOT/scripts/sync_maps_key.mjs" || true
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "IPA builds require macOS with Xcode." >&2
  exit 1
fi

DEFINES="${1:-release_defines.json}"
if [[ ! -f "$DEFINES" ]]; then
  echo "Missing $DEFINES — copy dart_defines.json.example or use release_defines.json" >&2
  exit 1
fi

echo "→ flutter pub get"
flutter pub get

echo "→ pod install"
(cd ios && pod install)

echo "→ flutter build ipa --release --dart-define-from-file=$DEFINES"
flutter build ipa --release "--dart-define-from-file=$DEFINES"

echo ""
echo "IPA: $ROOT/build/ios/ipa/"
ls -la "$ROOT/build/ios/ipa/" 2>/dev/null || true
echo "Upload with Transporter or Xcode Organizer."
