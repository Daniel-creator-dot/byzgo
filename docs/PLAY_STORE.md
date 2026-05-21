# Google Play Store — BytzGo Android

Everything in the repo for Play review:

| Item | Status |
|------|--------|
| Privacy policy URL | https://www.bytzgo.net/privacy (also https://byzgo-api.onrender.com/privacy) |
| Terms | https://www.bytzgo.net/terms |
| Account deletion | In-app + https://www.bytzgo.net/account-deletion |
| Data safety answers | [PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md) |
| Store listing text | [PLAY_STORE_LISTING.md](./PLAY_STORE_LISTING.md) |
| Signed AAB build | `npm run play:setup` |

Play requires a **signed App Bundle (`.aab`)**, not a debug-signed APK. Follow these steps in order.

## 1. One-time: upload keystore

From repo root:

```powershell
cd mobile
.\scripts\create_upload_keystore.ps1
```

- Creates `mobile/android/upload-keystore.jks` (gitignored).
- Copies `android/key.properties.example` → `android/key.properties` — set `storePassword` and `keyPassword`.
- **Back up** the `.jks` file and passwords. If you lose them, you cannot publish updates for the same app.

## 2. Register release SHA-1 (Maps, Sign-In, FCM)

```powershell
.\scripts\print_release_sha1.ps1
```

Add the **SHA-1** (and SHA-256 if asked) to:

| Where | What |
|-------|------|
| [Firebase](https://console.firebase.google.com/) → **bytzgo-9bd89** → Project settings → Your Android app | Add fingerprint |
| [Google Cloud Credentials](https://console.cloud.google.com/apis/credentials?project=bytzgo-9bd89) | Android OAuth client: package **`net.bytzgo.app`** + SHA-1 |
| Same project → **API key** used for Maps | Android restriction: package **`net.bytzgo.app`** + SHA-1 |

Without this step, **Google Sign-In** and **Maps** may work in debug but fail on the Play build.

## 3. Build the App Bundle

Production API default: `https://www.bytzgo.net` (override with `MOBILE_API_URL` in `.env.local`).

```powershell
# from repo root
npm run flutter:build:aab
```

Output:

`mobile/build/app/outputs/bundle/release/app-release.aab`

## 4. Play Console checklist

1. [Google Play Console](https://play.google.com/console) → **Create app** (if new).
2. **App ID (package name)** must match the build: **`net.bytzgo.app`** (cannot change after first upload).  
   - Add Firebase Android app + `google-services.json` — [FIREBASE_ANDROID_PACKAGE.md](./FIREBASE_ANDROID_PACKAGE.md).  
   - Run **`npm run play:validate`** before upload.
3. **Release** → **Production** (or **Internal testing** first) → **Create new release** → upload `app-release.aab`.
4. **Store listing**: short/long description, screenshots (phone), feature graphic, app icon.
5. **Privacy policy** URL (required) — e.g. `https://www.bytzgo.net/privacy` when hosted.
6. **App content** questionnaires:
   - Location (delivery / rider tracking)
   - Photos / camera (vendor menu, rider ID) — system picker / camera only
   - Notifications — ride alerts
   - Full-screen intent — incoming ride alerts when locked
7. **Target audience** and **News app / COVID** declarations as applicable.
8. **Data safety** form: account email, location, device IDs (FCM), etc.

## 5. Version bumps for each upload

Edit `mobile/pubspec.yaml`:

```yaml
version: 1.0.1+2   # 1.0.1 = versionName, +2 = versionCode (must increase every release)
```

Then rebuild the AAB.

## 6. Testing before production

- **Internal testing** track: add tester Gmail addresses, upload same AAB.
- Install from Play Store link; confirm login, maps, rider **Online**, and push with screen off.

## 7. Backend

Production API must stay up with Firebase FCM configured (see [FIREBASE_PUSH.md](./FIREBASE_PUSH.md)). Render service: **byzgo-api**.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Play rejects upload (debug signing) | Create `key.properties` + upload keystore; rebuild AAB |
| Google Sign-In error 10 on Play build | Add **release** SHA-1 to Firebase + OAuth Android client |
| Gray map on Play build | Maps API key Android restriction: `net.bytzgo.app` + release SHA-1 |
| No ride push | Rider Online; Render `FIREBASE_SERVICE_ACCOUNT_JSON`; reinstall from Play |
| Package / Firebase mismatch | Run `npm run play:validate` and [FIREBASE_ANDROID_PACKAGE.md](./FIREBASE_ANDROID_PACKAGE.md) |

## Scripts reference

| Script | Purpose |
|--------|---------|
| `create_upload_keystore.ps1` | Generate Play upload key |
| `print_release_sha1.ps1` | Fingerprints for Google/Firebase |
| `build_aab.ps1` | Signed release bundle |
| `build_apk.ps1` | Side-load APK (not for Play upload) |
