# Rotate Render API key

The previous API key was used in an agent session and should be revoked.

## Steps (Dashboard only — no API for key management)

1. Open [Render Account Settings → API Keys](https://dashboard.render.com/u/settings#api-keys)
2. **Revoke** the key that starts with `rnd_pzj7Xo...`
3. Click **Create API Key**, name it e.g. `bytzgo-ci`, copy the new key once
4. Store locally (never commit):

   ```bash
   # In repo-root .env.local (gitignored)
   RENDER_API_KEY=rnd_your_new_key_here
   ```

5. Export for shell scripts:

   ```bash
   export RENDER_API_KEY='rnd_your_new_key_here'
   ```

6. Test:

   ```bash
   curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
     'https://api.render.com/v1/services?limit=3' | head -c 200
   ```

Scripts that use `RENDER_API_KEY`: `scripts/redeploy-production.sh`, `scripts/setup-supabase-storage.ps1`.
