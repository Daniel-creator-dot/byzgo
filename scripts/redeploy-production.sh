#!/usr/bin/env bash
# Redeploy production API (byzgoback — www.bytzgo.net / bytzgo.net).
# Requires RENDER_API_KEY in the environment.
set -euo pipefail

SERVICE_ID="${1:-srv-d7use31o3t8c73fu3eig}"

if [[ -z "${RENDER_API_KEY:-}" ]]; then
  echo "Set RENDER_API_KEY first (Render Dashboard → Account Settings → API Keys)." >&2
  exit 1
fi

echo "Triggering deploy for ${SERVICE_ID} (byzgoback)..."
response="$(curl -fsS -X POST \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Accept: application/json" \
  "https://api.render.com/v1/services/${SERVICE_ID}/deploys")"

deploy_id="$(echo "$response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
status="$(echo "$response" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

echo "Deploy ${deploy_id:-unknown} status=${status:-unknown}"
echo "Wait ~2–3 min, then check:"
echo "  curl -s https://www.bytzgo.net/download/android/version"
echo "  curl -s -o /dev/null -w '%{http_code}' https://www.bytzgo.net/api/owner/dashboard  # expect 401"
