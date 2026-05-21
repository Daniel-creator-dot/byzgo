# Firebase — Android package `net.bytzgo.app`

Google Play requires a real package name (not `com.example.*`). BytzGo uses **`net.bytzgo.app`**.

## Automated setup (if service account has Firebase Management API)

```powershell
npm run setup:firebase:android
```

If that fails, use the manual steps below. SHA values: [GOOGLE_CLOUD_PLAY_SHA.md](./GOOGLE_CLOUD_PLAY_SHA.md).

## One-time setup (before Play upload)

1. Open [Firebase Console](https://console.firebase.google.com/) → project **bytzgo-9bd89**.
2. **Project settings** → **Your apps** → **Add app** → **Android**.
3. Package name: **`net.bytzgo.app`** (exactly).
4. Download **`google-services.json`** → replace:
   - `mobile/android/app/google-services.json`
5. Update `mobile/lib/firebase_options.dart` **android** `appId` from the new file (`mobilesdk_app_id`).
6. **Release SHA-1** (from `mobile/scripts/print_release_sha1.ps1`):
   - Firebase → Android app **net.bytzgo.app** → Add fingerprint
   - Google Cloud → Credentials → Android OAuth → package `net.bytzgo.app` + SHA-1
   - Maps API key → Android restriction → `net.bytzgo.app` + SHA-1
7. Rebuild: `npm run flutter:build:aab`

## iOS (later)

Bundle ID can stay or move to `net.bytzgo.app` separately in Firebase + Xcode.

## Old package `com.example.bytzgo`

Remove or ignore the old Firebase Android app after migration. Play listing must use **`net.bytzgo.app`** only.
