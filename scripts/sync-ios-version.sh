#!/usr/bin/env bash
# Sync ios-version.json from pubspec.yaml (parity with Android version marker).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$ROOT/mobile/pubspec.yaml"
OUT="$ROOT/public/ios-version.json"

version="$(grep '^version:' "$PUBSPEC" | awk '{print $2}')"
marketing="${version%%+*}"
build="${version#*+}"

cat > "$OUT" <<EOF
{
  "version": "$version",
  "marketing_version": "$marketing",
  "build_number": "$build",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "platform": "ios",
  "release_notes": "Okada & Keke passenger rides, rider vehicle type at signup, smarter dispatch matching.",
  "install_note": "Install from the App Store or TestFlight."
}
EOF

echo "Wrote $OUT ($version)"
if [[ -d "$ROOT/dist" ]]; then
  cp "$OUT" "$ROOT/dist/ios-version.json"
fi
