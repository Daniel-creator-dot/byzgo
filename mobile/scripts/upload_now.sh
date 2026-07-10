#!/usr/bin/env bash
# One command: build signed IPA and open Transporter for App Store Connect.
set -euo pipefail

MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MOBILE_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This must run on a Mac (Xcode + Transporter)." >&2
  exit 1
fi

export RUBYOPT="${RUBYOPT:--r logger}"
export PATH="${HOME}/.gem/ruby/2.6.0/bin:${HOME}/development/flutter/bin:${PATH}"

VER="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
BUILD="${VER#*+}"
MARKETING="${VER%%+*}"

echo "=========================================="
echo "  BytzGo iOS → App Store Connect"
echo "  Version: $VER"
echo "=========================================="

"$MOBILE_ROOT/scripts/manual_sign_app_store_ipa.sh"

IPA="$MOBILE_ROOT/build/ios/ipa/BytzGo.ipa"
[[ -f "$IPA" ]] || { echo "Missing IPA: $IPA"; exit 1; }

echo ""
echo "IPA ready: $IPA"
echo "App Store Connect → attach build $BUILD to version $MARKETING"
echo "Release notes: mobile/app_store_whats_new_${MARKETING}.txt"
echo ""

if [[ -d /Applications/Transporter.app ]]; then
  open -a Transporter "$IPA"
else
  echo "Install Transporter from the Mac App Store, then open: $IPA"
fi

REPO_ROOT="$(cd "$MOBILE_ROOT/.." && pwd)"
if [[ -f "$REPO_ROOT/.env.local" ]] && grep -q 'APPLE_APP_SPECIFIC_PASSWORD' "$REPO_ROOT/.env.local" 2>/dev/null; then
  echo "APPLE_APP_SPECIFIC_PASSWORD found — run: ./scripts/upload_app_store_ipa.sh"
fi
