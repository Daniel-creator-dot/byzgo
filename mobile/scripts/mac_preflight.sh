#!/usr/bin/env bash
# Mac preflight — run before upload. Fixes common issues automatically where possible.
set -euo pipefail
MOBILE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MOBILE_ROOT"

red() { echo "✗ $*"; }
green() { echo "✓ $*"; }

echo "BytzGo Mac upload preflight"
echo "==========================="

[[ "$(uname -s)" == "Darwin" ]] || { red "Not on macOS"; exit 1; }
green "macOS"

command -v xcodebuild >/dev/null && green "Xcode: $(xcodebuild -version | head -1)" || { red "Install Xcode from App Store"; exit 1; }
command -v flutter >/dev/null && green "Flutter: $(flutter --version | head -1)" || {
  red "Flutter not in PATH"
  echo "  Try: export PATH=\"\$PATH:\$HOME/development/flutter/bin\""
  exit 1
}
command -v pod >/dev/null && green "CocoaPods: $(pod --version)" || {
  echo "Installing CocoaPods..."
  sudo gem install cocoapods
}

green "Version: $(grep '^version:' pubspec.yaml)"
[[ -d /Applications/Transporter.app ]] && green "Transporter installed" || red "Install Transporter from Mac App Store"

echo ""
echo "Pull latest code:"
echo "  cd $(cd "$MOBILE_ROOT/.." && pwd) && git pull origin main"
echo ""
echo "Then double-click: mobile/UPLOAD_TO_APPLE.command"
echo "Or run: cd mobile && ./scripts/upload_now.sh"
