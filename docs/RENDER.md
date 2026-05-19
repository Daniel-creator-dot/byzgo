# Deploy BytzGo for Android + web (one host)

**bytzgo.net** must run the **Node Web Service** (API + web), not a static site only.  
Then the Flutter APK can use:

```properties
MOBILE_API_URL=https://bytzgo.net
```

## Deploy on Render

1. Push `main` with `render.yaml`.
2. Open: **https://dashboard.render.com/blueprint/new?repo=https://github.com/Daniel-creator-dot/byzgo**
3. If you already have a **Static Site** named `byzgo`:
   - Either delete it and apply this Blueprint, **or**
   - Change it to a **Web Service** with:
     - Build: `npm install && npm run build && npm install --prefix backend`
     - Start: `npm run start:render`
     - Health: `/api/health`
4. Set secrets: `DATABASE_URL`, `JWT_SECRET`, `GOOGLE_MAPS_API_KEY`, Paystack, SMS.
5. Custom domain: **bytzgo.net** / **www.bytzgo.net** on this service.

## Verify (required for Android)

```bash
curl https://bytzgo.net/api/health
```

Expected: `{"ok":true,"service":"bytzgo-api"}` — **not** HTML.

## Build Android APK

```powershell
npm run flutter:build:apk
```

Uses `https://bytzgo.net` by default. Install:

```powershell
adb install mobile\build\app\outputs\flutter-apk\app-release.apk
```

## Local emulator (PC backend)

```powershell
npm run backend
cd mobile
..\.flutter-sdk\bin\flutter run -d emulator-5554 --dart-define-from-file=dart_defines.json --dart-define=API_URL=http://10.0.2.2:3000
```
