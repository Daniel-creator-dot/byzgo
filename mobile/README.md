# BytzGo Mobile (Flutter)

Cross-platform iOS and Android client for **BytzGo** — **Bolt / Uber–style** bike delivery UI (full-screen map, white bottom sheet, green accent). Uses the same **Express API** and **Socket.IO** events as the React web app in the repo root.

## What's included

| Layer | Status |
|-------|--------|
| Email/password login → `POST /api/auth/login` | Done |
| Google sign-in → `POST /api/auth/google` | Optional (`GOOGLE_WEB_CLIENT_ID` + FlutterFire) |
| JWT in secure storage | Done |
| Socket.IO (`join`, `order:updated`, `ride:incoming`, …) | Done |
| Role routing (customer / rider / vendor / admin) | Done |
| Google Maps (or painted fallback) | Done |
| Customer book courier → `POST /api/orders` | Done |
| Rider go online → `PATCH /api/auth/status` (`is_online`) | Done |
| Rider KYC upload (licence, Ghana card, photo JPEG) | Done |
| Rider accept / decline → `PATCH` / `POST decline` | Done |
| Live location while online → Socket `location:update` | Done |
| Admin control tower (live map, fleet, orders, insights) | Done |
| Admin driver verification (approve / reject) | Done |
| Live online drivers on map + socket GPS updates | Done |
| Vendor | Map shell stub |

## Prerequisites

1. [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable, 3.24+) — add `flutter\bin` to **PATH**
2. Android Studio (Android SDK) and/or Xcode on macOS for iOS
3. Backend: `npm run backend` from repo root (port **3000**)
4. Env: root `.env.example` and `backend/.env`

## First-time setup

```powershell
cd mobile
.\scripts\setup_platform.ps1   # runs flutter create . if Flutter is on PATH
flutter pub get
```

If `android/` was created manually, copy `android\local.properties.example` → `android\local.properties` and set:

```properties
flutter.sdk=C:\\path\\to\\flutter
sdk.dir=C:\\Users\\YOU\\AppData\\Local\\Android\\Sdk
GOOGLE_MAPS_API_KEY=your-maps-sdk-key
```

### Google Maps

Your web app key in **repo root** [`.env.local`](../.env.local) (`GOOGLE_MAPS_API_KEY` or `VITE_GOOGLE_MAPS_API_KEY`) is used for mobile too.

**One-time sync** (copies key into Android, iOS, and Dart):

```powershell
cd mobile
.\scripts\sync_maps_key.ps1
```

In [Google Cloud Console](https://console.cloud.google.com/), enable for the same project:

- **Maps SDK for Android**
- **Maps SDK for iOS**
- (Web already uses Maps JavaScript API)

Then rebuild (use the repo **`.flutter-sdk`** so Gradle and CLI match):

```powershell
# from repo root — recommended
npm run backend          # terminal 1
npm run flutter:android  # terminal 2 (emulator or device)

# or from mobile/
..\.flutter-sdk\bin\flutter clean
..\.flutter-sdk\bin\flutter pub get
..\.flutter-sdk\bin\flutter run --dart-define-from-file=dart_defines.json --dart-define=API_URL=http://10.0.2.2:3000
```

Android also reads `../../.env.local` at build time if `local.properties` has no key.

**If the map is gray or blank:** In Google Cloud, enable **Maps SDK for Android** (not only JavaScript API). For restricted keys, add an **Android** restriction with package `com.bytzgo.bytzgo_mobile` and your debug SHA-1 fingerprint.

### API URL (`--dart-define`)

| Environment | `API_URL` |
|-------------|-----------|
| Android emulator → PC | `http://10.0.2.2:3000` |
| iOS simulator → PC | `http://127.0.0.1:3000` |
| Physical device (same Wi‑Fi) | `http://<PC-LAN-IP>:3000` |
| Production | `https://your-api.onrender.com` |

Default (no define): `http://10.0.2.2:3000`.

## Run locally

```powershell
# Terminal 1 — API (repo root)
npm run backend

# Terminal 2 — Flutter
cd mobile
flutter run ^
  --dart-define=API_URL=http://10.0.2.2:3000 ^
  --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
```

### End-to-end smoke test

1. Start backend: `npm run backend` (repo root).
2. Log in as **customer** on mobile → allow location → set drop-off (tap map) → **Request bike**.
3. Log in as **rider** (second device/emulator) → **Go online** → accept incoming job.
4. Customer should see “Your rider is on the way” via socket `order:updated`.

## App icon

Branding lives in [`assets/branding/`](assets/branding/). Replace `app_icon_source.png` with the official **BytzGO** wordmark (black background), then regenerate launcher icons and `app_logo.png` for in-app UI.

Regenerate after replacing `app_icon_source.png`:

```powershell
npm run icons
# or: python mobile/scripts/generate_app_icon.py
```

Updates Android mipmaps (black launcher background), Flutter web PWA icons, `app_logo.png`, and `public/icon-*.png` + `public/app-logo.png` for the web app.

## Analyze & test

```powershell
cd mobile
flutter analyze
flutter test
```

## Google Sign-In (optional)

Email login works **without** Firebase.

1. Install FlutterFire CLI:
   ```powershell
   dart pub global activate flutterfire_cli
   ```
2. From `mobile/`:
   ```powershell
   flutterfire configure
   ```
   This replaces [`lib/firebase_options.dart`](lib/firebase_options.dart). Set `isConfigured = true` in the generated file (or remove the stub flag per FlutterFire output).
3. **Android Google Sign-In (required for “Continue with Google” on APK):**

   Error `PlatformException(sign_in_failed … : 10)` means the APK signing certificate is not in Google Cloud.

   ```powershell
   .\mobile\scripts\print_google_signin_android.ps1
   ```

   Then [Google Cloud Credentials](https://console.cloud.google.com/apis/credentials?project=bytzgo-72f1c) → **Create credentials** → **OAuth client ID** → **Android**:

   - Package: `com.bytzgo.bytzgo_mobile`
   - SHA-1: from the script (debug keystore if you install the release APK built on this PC)

   Keep your existing **Web** client for `GOOGLE_WEB_CLIENT_ID` / `serverClientId`.

4. Firebase FCM (ride alerts when screen is off): `google-services.json` and `GoogleService-Info.plist` are in `android/app/` and `ios/Runner/` for project **bytzgo-9bd89**. See [docs/FIREBASE_PUSH.md](../docs/FIREBASE_PUSH.md). Backend needs `backend/firebase-service-account.json` from Firebase Console.
5. Run with web client ID:
   ```powershell
   flutter run ^
     --dart-define=API_URL=http://10.0.2.2:3000 ^
     --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
   ```

Until `GOOGLE_WEB_CLIENT_ID` is set, the Google button is hidden on the login screen.

## Project layout

```text
mobile/lib/
  main.dart
  firebase_bootstrap.dart
  firebase_options.dart      # stub until flutterfire configure
  app.dart
  core/                      # api, session, socket, env
  models/
  features/
  routing/
  shared/
```

## Build APK for your phone

Physical devices cannot use `localhost` or `10.0.2.2`. Point the app at a **reachable** API:

1. In repo [`.env.local`](../.env.local) set:
   ```properties
   MOBILE_API_URL=https://your-public-api-host
   ```
   (Or `http://<your-PC-LAN-IP>:3000` if the phone is on the same Wi‑Fi and `npm run backend` is running.)

2. Sync keys and build:
   ```powershell
   npm run flutter:build:apk
   ```

3. Install:
   ```powershell
   adb install mobile\build\app\outputs\flutter-apk\app-release.apk
   ```
   Or copy `app-release.apk` to the phone and open it.

Template for local defines: [`dart_defines.json.example`](dart_defines.json.example) (copy to `dart_defines.json`, gitignored).

**Google Cloud:** For release APKs, restrict your Maps key to Android app `com.bytzgo.bytzgo_mobile` + your release SHA-1. Enable **Places API** and **Geocoding API** (address search uses the backend).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `flutter` not recognized | Install Flutter and add to PATH; restart terminal |
| No `android/` / incomplete `ios/` | Run `.\scripts\setup_platform.ps1` or `flutter create . --org com.bytzgo --project-name bytzgo_mobile` |
| `flutter.sdk not set` | Create `android/local.properties` from example |
| Connection refused (emulator) | Use `10.0.2.2:3000`, not `localhost` |
| Connection refused (phone APK) | Rebuild with `MOBILE_API_URL` set to your public API or PC LAN IP |
| Address search empty | Backend needs `GOOGLE_MAPS_API_KEY`; enable Places + Geocoding APIs |
| CardTheme / analyzer errors | Run `flutter pub get` after pulling |
| Google button missing | Expected until `GOOGLE_WEB_CLIENT_ID` is passed |

## Related

- Web app: repo root
- Backend: [`backend/server.ts`](../backend/server.ts)
- **Production deploy:** [`docs/RENDER.md`](../docs/RENDER.md)
