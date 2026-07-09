#!/usr/bin/env bash
# One command: build v1.0.50 (69) IPA and open Transporter.
# Run on your Mac in Terminal:
#   cd /path/to/byzgo/mobile && ./scripts/upload_now.sh
set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MOBILE_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This must run on a Mac (Xcode + Transporter)." >&2
  exit 1
fi

echo "=========================================="
echo "  BytzGo iOS → App Store Connect"
echo "  Version: $(grep '^version:' pubspec.yaml)"
echo "=========================================="

"$MOBILE_ROOT/scripts/build_app_store_ipa.sh"

IPA="$(ls -1 "$MOBILE_ROOT/build/ios/ipa"/*.ipa 2>/dev/null | head -1)"
if [[ -z "$IPA" ]]; then
  echo "No IPA found. Try: ./scripts/build_app_store_ipa.sh --open-xcode"
  exit 1
fi

echo ""
echo "IPA ready: $IPA"
echo ""
echo "Opening Transporter — drag the IPA if it does not auto-load."
echo "After upload, App Store Connect → build 69 → version 1.0.50"
echo "Release notes: mobile/app_store_whats_new_1.0.50.txt"
echo ""

if [[ -d /Applications/Transporter.app ]]; then
  open -a Transporter "$IPA"
else
  echo "Install Transporter from the Mac App Store, then open:"
  echo "  $IPA"
fi

# Optional auto-upload if app-specific password is in repo-root .env.local
REPO_ROOT="$(cd "$MOBILE_ROOT/.." && pwd)"
if [[ -f "$REPO_ROOT/.env.local" ]] && grep -q 'APPLE_APP_SPECIFIC_PASSWORD' "$REPO_ROOT/.env.local" 2>/dev/null; then
  read -r -p "Upload automatically with altool? [y/N] " ans
  if [[ "${ans,,}" == "y" ]]; then
    "$MOBILE_ROOT/scripts/upload_app_store_ipa.sh"
  fi
fi
