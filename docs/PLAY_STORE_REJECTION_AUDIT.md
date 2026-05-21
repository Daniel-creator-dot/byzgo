# Play Store rejection audit — BytzGo

Use this before uploading `app-release.aab`. Items marked **fixed in repo** are handled in code; **you do in Console** are Play Console / Firebase steps.

## Critical (will reject if wrong)

| Check | Status | Action |
|-------|--------|--------|
| Package name `com.example.*` | **Fixed** → `net.bytzgo.app` | Play blocks `com.example` for production. Create **new** Play app with this package (first upload only). |
| Firebase `google-services.json` matches package | **You do in Firebase** | [FIREBASE_ANDROID_PACKAGE.md](./FIREBASE_ANDROID_PACKAGE.md) — add Android app `net.bytzgo.app`, download new JSON, add release SHA-1. |
| Signed release AAB (not debug) | **You do locally** | `npm run flutter:build:aab` with `android/key.properties` |
| Privacy policy URL works | **Fixed** | https://www.bytzgo.net/privacy |
| Account deletion | **Fixed** | In-app + https://www.bytzgo.net/account-deletion |

## Permissions (policy)

| Permission | Status | Play declaration |
|------------|--------|------------------|
| Location (fine/coarse) | Required | Data safety + “App functionality” — delivery tracking |
| POST_NOTIFICATIONS | Required | Data safety — order/ride alerts |
| CAMERA | Via image_picker | Photo picker / KYC — declare photos in Data safety |
| READ_MEDIA / broad storage | **Removed** | Use system photo picker only (Play photo policy) |
| USE_FULL_SCREEN_INTENT | Required for ride alerts | Declare in App content → special access |
| WAKE_LOCK | From FCM/notifications | Normal for push; declare in Data safety if asked |

## Target API

| Check | Status |
|-------|--------|
| targetSdk 35 | **Fixed** in `build.gradle.kts` |
| 64-bit ABIs | AAB includes arm64-v8a by default |

## Store listing (you do in Console)

- [ ] Short + full description ([PLAY_STORE_LISTING.md](./PLAY_STORE_LISTING.md))
- [ ] 2+ phone screenshots
- [ ] Feature graphic 1024×500
- [ ] App icon 512×512
- [ ] Contact email: `jerryanthony61@gmail.com` or `support@bytzgo.com`
- [ ] Category: Maps & Navigation or Food & Drink
- [ ] **Data safety** ([PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md))
- [ ] **Ads**: No, app does not contain ads
- [ ] **Target audience**: Not designed for children under 13
- [ ] **News / Health / Financial** declarations: No (unless you add those features)
- [ ] **Export compliance**: Standard encryption (HTTPS) — typically “No” for US export paperwork in questionnaire

## After package change

1. Firebase new Android app + `google-services.json`
2. Google Cloud OAuth Android client: package `net.bytzgo.app` + release SHA-1
3. Maps API key restriction: same package + SHA-1
4. Rebuild AAB: `npm run flutter:build:aab`
5. **New** Play Console app (cannot reuse listing from `com.example.bytzgo`)

Validate locally:

```powershell
cd mobile
.\scripts\validate_play_release.ps1
```
