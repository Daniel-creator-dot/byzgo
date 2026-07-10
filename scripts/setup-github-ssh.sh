#!/usr/bin/env bash
# Configure SSH for GitHub and add this machine's key as a repo deploy key (if token allows).
set -euo pipefail

KEY="$HOME/.ssh/id_ed25519"
PUB="${KEY}.pub"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "$(whoami)@$(hostname -s)"
fi

if ! grep -q 'Host github.com' "$HOME/.ssh/config" 2>/dev/null; then
  cat >> "$HOME/.ssh/config" <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  AddKeysToAgent yes
EOF
  chmod 600 "$HOME/.ssh/config"
fi

eval "$(ssh-agent -s)" >/dev/null
ssh-add "$KEY" 2>/dev/null || true

echo "Public key:"
cat "$PUB"
echo ""

# Try account SSH key (needs admin:public_key) or repo deploy key (works with repo scope).
TOKEN=""
if git credential-osxkeychain get >/dev/null 2>&1 <<'EOF'
protocol=https
host=github.com
EOF
then
  TOKEN=$(git credential-osxkeychain get 2>/dev/null <<'EOF' | awk -F= '/^password=/{print $2}'
protocol=https
host=github.com
EOF
)
fi

if [[ -n "$TOKEN" ]]; then
  RESP=$(curl -s -X POST "https://api.github.com/repos/Daniel-creator-dot/byzgo/keys" \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'title':'macbookpro-deploy-key','key':open('$PUB').read().strip(),'read_only':False}))")")
  if echo "$RESP" | grep -q '"id"'; then
    echo "✓ Deploy key added to Daniel-creator-dot/byzgo"
  else
    echo "Deploy key API: $(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',d))" 2>/dev/null || echo "$RESP")"
    echo "Add the public key manually: https://github.com/settings/ssh/new"
    pbcopy < "$PUB" 2>/dev/null && echo "(copied to clipboard)"
    open "https://github.com/settings/ssh/new" 2>/dev/null || true
  fi
else
  pbcopy < "$PUB" 2>/dev/null && echo "Copied public key to clipboard."
  open "https://github.com/settings/ssh/new" 2>/dev/null || true
fi

echo ""
ssh -T git@github.com 2>&1 | head -2 || true
echo "Test push: git push origin main"
