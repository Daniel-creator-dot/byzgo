#!/usr/bin/env bash
# Mac only: restart backend + run BytzGo on iPhone Simulator.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MOBILE="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS Simulator requires macOS + Xcode." >&2
  exit 1
fi

# --- Backend (repo root) ---
echo "Stopping old backend on port 3000..."
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
sleep 1

if [[ -f "$REPO/backend/.env" ]]; then
  echo "Starting backend (npm run backend)..."
  cd "$REPO"
  npm run backend &
  BACKEND_PID=$!
  sleep 3
  API_URL="http://127.0.0.1:3000"
else
  echo "No backend/.env — using production API (https://www.bytzgo.net)"
  API_URL="https://www.bytzgo.net"
  BACKEND_PID=""
fi

# --- Flutter ---
cd "$MOBILE"
if [[ ! -f dart_defines.json ]]; then
  cp dart_defines.json.example dart_defines.json
fi

flutter pub get
cd ios && pod install && cd ..

echo "Opening Simulator..."
open -a Simulator 2>/dev/null || true

echo "Building & running on iOS Simulator (API: $API_URL)..."
flutter run -d ios \
  --dart-define-from-file=dart_defines.json \
  --dart-define=API_URL="$API_URL"

if [[ -n "${BACKEND_PID:-}" ]]; then
  kill "$BACKEND_PID" 2>/dev/null || true
fi
