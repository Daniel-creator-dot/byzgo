# Render — fix bytzgo.net for Flutter APK

## The problem

If this returns **HTML** (login page) instead of JSON:

```bash
curl https://bytzgo.net/api/health
```

then **bytzgo.net** is attached to a **Static Site** (Vite `dist/`), not the **Node Web Service**.  
Static sites serve `index.html` for every path, including `/api/*`, so the **APK cannot log in**.

Expected (Node API):

```json
{"ok":true,"service":"bytzgo-api","client":"flutter"}
```

Verify locally:

```powershell
.\scripts\verify-render-api.ps1
```

---

## Fix in Render Dashboard (required)

You cannot “add API routes” to a Static Site. You need a **Web Service** running Express.

### Step 1 — Open your services

1. Go to [Render Dashboard](https://dashboard.render.com/).
2. Find services named **byzgo** (or similar).

### Step 2 — Identify the wrong service

| Type | What you see | Problem |
|------|----------------|--------|
| **Static Site** | Publish directory `dist` or `npm run build` | Serves HTML for `/api/health` |
| **Web Service** | Root dir `backend`, start `npm start` | Correct for APK |

If **bytzgo** is a **Static Site**, that is what’s breaking the APK.

### Step 3 — Create or fix the Web Service

**Option A — Blueprint (recommended)**

1. Push this repo to GitHub (includes `render.yaml`).
2. Open:  
   [Create Blueprint from repo](https://dashboard.render.com/blueprint/new?repo=https://github.com/Daniel-creator-dot/byzgo)
3. Click **Apply** → creates/updates **byzgo** as **Web Service**.
4. Set secrets when prompted:
   - `DATABASE_URL`
   - `JWT_SECRET`
   - `GOOGLE_MAPS_API_KEY` / `VITE_GOOGLE_MAPS_API_KEY`
   - `PAYSTACK_PUBLIC_KEY`, `PAYSTACK_SECRET_KEY`
   - `SMS_API_KEY`
5. Wait until deploy status is **Live**.

**Option B — Manual Web Service**

1. **New +** → **Web Service** → connect this Git repo.
2. Settings:

   | Field | Value |
   |-------|--------|
   | **Name** | `byzgo` |
   | **Runtime** | Node |
   | **Root Directory** | `backend` |
   | **Build Command** | `npm ci` |
   | **Start Command** | `npm start` |
   | **Health Check Path** | `/api/health` |

3. **Environment** → add variables from `backend/.env` (at minimum `DATABASE_URL`, `JWT_SECRET`).
4. Set `NODE_ENV` = `production`, `SERVE_WEB` = `false` (API-only for Flutter).

### Step 4 — Point **bytzgo.net** at the Web Service

1. Open the **Web Service** (not the Static Site).
2. **Settings** → **Custom Domains** → add **bytzgo.net** (and `www` if you use it).
3. Update DNS at your registrar to Render’s targets (shown in Dashboard).
4. On the **Static Site** (if it still exists): **remove** **bytzgo.net** from its custom domains, or **delete** the Static Site so only one service owns the domain.

### Step 5 — Verify

```powershell
.\scripts\verify-render-api.ps1
```

Or:

```bash
curl -s https://bytzgo.net/api/health
```

You must see JSON with `"ok":true`.

### Step 6 — Rebuild APK (after API is live)

```powershell
npm run flutter:build:apk
adb install -r mobile\build\app\outputs\flutter-apk\app-release.apk
```

APK uses `MOBILE_API_URL=https://bytzgo.net` by default (`mobile/scripts/build_apk.ps1`).

---

## What `render.yaml` deploys

Single **Web Service** — API only (`SERVE_WEB=false`). No Vite/React on Render.

| Setting | Value |
|---------|--------|
| Root dir | `backend` |
| Build | `npm ci` |
| Start | `npm start` |
| Health | `/api/health` |

---

## Flutter development

| Target | Command |
|--------|---------|
| Phone APK (production API) | `npm run flutter:build:apk` then install APK |
| Emulator + PC API | `npm run backend` then `npm run app` |

Do **not** use `npm run dev` for mobile — that starts legacy Vite web UI only.

---

## Free tier note

Render free Web Services **spin down** after ~15 minutes idle. First APK request after idle may take 30–60s (cold start). Upgrade plan or use a uptime ping if you need always-on.

---

## Repo layout

| Path | Role |
|------|------|
| `mobile/` | Flutter app (APK) |
| `backend/` | Express + Socket.IO API |
| `render.yaml` | Render Blueprint |
| `src/` | Legacy React web (not deployed for APK) |
