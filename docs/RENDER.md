# Render — API for the Flutter app

The **customer/rider app is Flutter** (`mobile/`). Render hosts the **Express API only** — not the old React/Vite site in `src/`.

## Flutter on your phone

APK (production API baked in):

```powershell
npm run flutter:build:apk
adb install mobile\build\app\outputs\flutter-apk\app-release.apk
```

Default API: `https://bytzgo.net`

## Flutter on emulator (PC backend)

```powershell
npm run backend          # terminal 1
npm run app              # terminal 2 — same as flutter:android
```

Or Chrome (Flutter web):

```powershell
npm run backend
npm run flutter:chrome
```

Do **not** use `npm run dev` for the mobile app — that starts Vite (legacy web UI).

## Deploy API on Render

1. In Render Dashboard, change **byzgo** from **Static Site** → **Web Service** (or apply Blueprint after push).
2. Settings:
   - **Build:** `npm install --prefix backend`
   - **Start:** `npm run start:render`
   - **Health:** `/api/health`
3. Env: `DATABASE_URL`, `JWT_SECRET`, `GOOGLE_MAPS_API_KEY`, Paystack, SMS (from `backend/.env`).
4. Custom domain **bytzgo.net** on this service.

Verify:

```bash
curl https://bytzgo.net/api/health
# {"ok":true,"service":"bytzgo-api","client":"flutter"}
```

## Repo layout

| Path | What it is |
|------|------------|
| `mobile/` | **Flutter app** (use this) |
| `backend/` | API + Socket.IO for Flutter |
| `src/` | Legacy React web (not used for mobile) |
