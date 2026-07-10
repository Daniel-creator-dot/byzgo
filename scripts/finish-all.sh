#!/usr/bin/env bash
# Run remaining production tasks when .env.local is filled in.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env.local"

load_env() {
  [[ -f "$ENV_FILE" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source <(grep -E '^\s*[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | sed 's/^\s*//')
  set +a
}

echo "=== BytzGo finish-all ==="

# --- Production health (always) ---
HEALTH=$(curl -sf "https://www.bytzgo.net/api/health" || true)
if [[ -n "$HEALTH" ]]; then
  echo "$HEALTH" | python3 -c "
import sys, json
d = json.load(sys.stdin)
db = d.get('database', {})
print('API:', d.get('service'), '| regionAligned:', db.get('regionAligned'), '| poolMax:', db.get('poolMax'))
" 2>/dev/null || echo "Health: $HEALTH"
else
  echo "WARN: https://www.bytzgo.net/api/health unreachable"
fi

# --- Cloudflare apex DNS ---
fix_cloudflare_dns() {
  local token="$1"
  local zone name record_id payload
  zone=$(curl -sf -H "Authorization: Bearer $token" \
    "https://api.cloudflare.com/client/v4/zones?name=bytzgo.net" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')")
  [[ -n "$zone" ]] || { echo "Cloudflare: zone bytzgo.net not found"; return 1; }

  record_id=$(curl -sf -H "Authorization: Bearer $token" \
    "https://api.cloudflare.com/client/v4/zones/$zone/dns_records?type=CNAME&name=bytzgo.net" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('result',[]):
  if r.get('name') in ('bytzgo.net','@'):
    print(r['id']); break
")

  payload=$(python3 -c "import json; print(json.dumps({'type':'CNAME','name':'bytzgo.net','content':'byzgoback-eu.onrender.com','proxied':True,'ttl':1}))")

  if [[ -n "$record_id" ]]; then
    curl -sf -X PUT "https://api.cloudflare.com/client/v4/zones/$zone/dns_records/$record_id" \
      -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$payload" >/dev/null
    echo "Cloudflare: updated bytzgo.net → byzgoback-eu.onrender.com"
  else
    curl -sf -X POST "https://api.cloudflare.com/client/v4/zones/$zone/dns_records" \
      -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$payload" >/dev/null
    echo "Cloudflare: created bytzgo.net → byzgoback-eu.onrender.com"
  fi

  sleep 3
  dig +short bytzgo.net CNAME || true
}

# --- App Store upload ---
upload_ipa() {
  export APPLE_ID="${APPLE_ID:-jerryanthony61@gmail.com}"
  export APPLE_APP_SPECIFIC_PASSWORD
  "$ROOT/mobile/scripts/upload_app_store_ipa.sh"
}

if load_env; then
  if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    fix_cloudflare_dns "$CLOUDFLARE_API_TOKEN" || echo "Cloudflare DNS update failed"
  else
    echo "Skip DNS: set CLOUDFLARE_API_TOKEN in .env.local (optional — www.bytzgo.net already works)"
  fi

  if [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    upload_ipa || echo "App Store upload failed"
  else
    echo "Skip upload: set APPLE_APP_SPECIFIC_PASSWORD in .env.local"
    if [[ -d /Applications/Transporter.app ]] && [[ -f "$ROOT/mobile/build/ios/ipa/BytzGo.ipa" ]]; then
      open -a Transporter "$ROOT/mobile/build/ios/ipa/BytzGo.ipa" 2>/dev/null || true
      echo "Opened Transporter — click Deliver for build $(grep '^version:' "$ROOT/mobile/pubspec.yaml" | awk '{print $2}')"
    fi
  fi

  if [[ -n "${RENDER_API_KEY:-}" ]]; then
    curl -sf -H "Authorization: Bearer $RENDER_API_KEY" "https://api.render.com/v1/services?limit=1" >/dev/null \
      && echo "Render API key: valid" || echo "Render API key: invalid"
  else
    echo "Skip Render test: set RENDER_API_KEY in .env.local after rotating in Dashboard"
  fi
else
  echo ""
  echo "No .env.local found."
  echo "  cp finish-setup.env.example .env.local"
  echo "  # fill in APPLE_APP_SPECIFIC_PASSWORD (required for auto-upload)"
  echo "  ./scripts/finish-all.sh"
  if [[ -d /Applications/Transporter.app ]] && [[ -f "$ROOT/mobile/build/ios/ipa/BytzGo.ipa" ]]; then
    open -a Transporter "$ROOT/mobile/build/ios/ipa/BytzGo.ipa" 2>/dev/null || true
    echo "Opened Transporter as fallback."
  fi
fi

echo ""
echo "Done. Release notes: mobile/app_store_whats_new_1.0.51.txt"
