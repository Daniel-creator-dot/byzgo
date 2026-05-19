# Deploy BytzGo on Render

Your domain **bytzgo.net** currently points at a **static site only** (`byzgo.onrender.com`). The Express API must be deployed as a separate **Web Service** so Flutter, the web app, and mobile can call `/api/...`.

## One-time setup

### 1. Push the Blueprint

```bash
git add render.yaml docs/RENDER.md backend/server.ts
git commit -m "Add Render blueprint for API and static web"
git push origin main
```

### 2. Apply the Blueprint

Open (after push):

**https://dashboard.render.com/blueprint/new?repo=https://github.com/Daniel-creator-dot/byzgo**

1. Connect GitHub if prompted.
2. Review two services:
   - **bytzgo-api** — Node backend (`backend/`)
   - **byzgo** — Vite static site (`dist/`)
3. Fill **secret** env vars (`sync: false`):
   - `DATABASE_URL` — Supabase/Postgres connection string
   - `JWT_SECRET`
   - `GOOGLE_MAPS_API_KEY` (and duplicate as `VITE_GOOGLE_MAPS_API_KEY` on API if needed)
   - Paystack keys, `SMS_API_KEY`, etc. (copy from `backend/.env`)
4. Click **Apply** and wait until both services are **Live**.

### 3. Custom domains

| Service     | Suggested domain   | Already configured?      |
|------------|--------------------|---------------------------|
| **byzgo**  | `bytzgo.net`, `www` | Yes → `byzgo.onrender.com` |
| **bytzgo-api** | `api.bytzgo.net` | Add in Render → Settings → Custom Domains |

### 4. Verify API

```bash
curl https://bytzgo-api.onrender.com/api/health
# {"ok":true,"service":"bytzgo-api"}

curl https://bytzgo-api.onrender.com/api/config/maps-health
# JSON (not HTML)
```

### 5. Flutter APK / phone

In repo `.env.local`:

```properties
MOBILE_API_URL=https://bytzgo-api.onrender.com
```

Or after adding `api.bytzgo.net`:

```properties
MOBILE_API_URL=https://api.bytzgo.net
```

Build:

```powershell
npm run flutter:build:apk
```

## If you already have a `byzgo` static service

Applying the Blueprint may **update** the existing static site or create a new one. In the Dashboard:

- Keep **bytzgo.net** on the static **byzgo** service.
- Do **not** point the domain at **bytzgo-api** (API only).

## Free tier notes

- Web services spin down after ~15 minutes idle; first request may be slow.
- Use **bytzgo-api** URL in the mobile app, not `www.bytzgo.net`, until you add a reverse proxy.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| `/api/*` returns HTML on bytzgo.net | Expected on static site — use **bytzgo-api** URL for API |
| Health check fails | Ensure `DATABASE_URL` is set; check deploy logs |
| Maps autocomplete empty | Set `GOOGLE_MAPS_API_KEY` on **bytzgo-api**; enable Places + Geocoding APIs |
| Web login works, Flutter not | Rebuild APK with correct `MOBILE_API_URL` |
