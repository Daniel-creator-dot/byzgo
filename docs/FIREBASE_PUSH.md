# Firebase push notifications (FCM)

Riders get **incoming job alerts when the app is closed or the screen is off** after mobile + backend Firebase are linked to the same project.

## Mobile app (bytzgo-9bd89)

Config files are wired for package **`com.example.bytzgo`**:

| File | Location |
|------|----------|
| `google-services.json` | `mobile/android/app/google-services.json` |
| `GoogleService-Info.plist` | `mobile/ios/Runner/GoogleService-Info.plist` |
| Dart options | `mobile/lib/firebase_options.dart` |

Rebuild and reinstall the APK after any Firebase change:

```powershell
cd mobile
.\scripts\build_apk.ps1
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

On the phone:

1. **Settings → Apps → BytzGo → Notifications** → allow all.
2. Rider: open app, log in, go **Online** (registers FCM token).
3. Disable battery restrictions for BytzGo if alerts are delayed (Samsung/Xiaomi “Unrestricted”).

## Backend (required for server → phone push)

The API must send FCM using a **Firebase Admin service account** from the **same project** (`bytzgo-9bd89`).

1. [Firebase Console](https://console.firebase.google.com/) → project **bytzgo-9bd89**.
2. **Project settings** → **Service accounts** → **Generate new private key**.
3. Save locally as `backend/firebase-service-account.json` (gitignored).

4. **Render** — pick one:

   **Option A — Secret file (recommended)**  
   - Dashboard → **byzgo-api** ([web service](https://dashboard.render.com/web/srv-d86e8qv7f7vs7395kgrg)) → **Environment** → **Secret Files** → **Add**  
   - Upload `bytzgo-9bd89-firebase-adminsdk-*.json`  
   - Filename on disk: `firebase-service-account.json`  
   - Add env var: `FIREBASE_SERVICE_ACCOUNT_PATH=/etc/secrets/firebase-service-account.json`

   **Option B — Secret env var**  
   - Add `FIREBASE_SERVICE_ACCOUNT_JSON` = entire JSON file contents (one line; Render “Secret”)

5. Set `FIREBASE_PROJECT_ID=bytzgo-9bd89` on Render.

6. Redeploy. Logs must show: `Firebase Admin initialized … FCM enabled`.

## Package name note

If you create a **new** Android app in Firebase with a different package (e.g. `com.bytzgo.bytzgo_mobile`), download a new `google-services.json` and update `applicationId` in `mobile/android/app/build.gradle.kts` to match.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No alerts when app closed | Backend missing service account JSON; rider not online; notification permission denied |
| Token never registered | Reinstall APK; check log `FCM token registered` |
| Old project tokens | Users must reopen app after project migration so tokens refresh |
