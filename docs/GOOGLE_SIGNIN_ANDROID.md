# Google Sign-In on Android (sideload APK)

## Why "Google Sign-In is not set up for this build"

Android returns error **10** when the APK signing certificate SHA-1 is not registered in Firebase for package `net.bytzgo.app`.

Public APKs from https://www.bytzgo.net/download/android are signed with **`mobile/android/bytzgo-sideload.jks`** (committed in the repo).

## One-time Firebase registration (required)

1. Put a Firebase Admin service account JSON in `backend/firebase-service-account.json` (from Firebase Console → Project settings → Service accounts).

2. From repo root:

```bash
npm run setup:firebase:android
```

This registers all known SHA-1 fingerprints (release, debug, **sideload APK**) and refreshes `google-services.json`.

3. Rebuild and deploy the APK:

```bash
bash mobile/scripts/build_apk.sh https://www.bytzgo.net
git add public/bytzgo.apk public/android-version.json mobile/pubspec.yaml
```

## Manual registration (no service account)

1. Open [Firebase → bytzgo-9bd89 → Project settings](https://console.firebase.google.com/project/bytzgo-9bd89/settings/general).

2. Select Android app **net.bytzgo.app**.

3. **Add fingerprint** → SHA-1:

```
EC:E9:76:BB:77:E6:87:63:44:22:DB:A1:DD:58:05:25:22:FA:45:0A
```

4. Download the updated `google-services.json` and replace `mobile/android/app/google-services.json`.

5. Rebuild the APK (see above).

## Verify local SHA-1

```bash
bash mobile/scripts/print_google_signin_android.sh
```

Sideload keystore:

```bash
keytool -list -v -keystore mobile/android/bytzgo-sideload.jks -alias bytzgo -storepass bytzgo-sideload | grep SHA1
```

## Server

Production must have `GOOGLE_SIGN_IN_ENABLED=true` on Render (see `render.yaml`).
