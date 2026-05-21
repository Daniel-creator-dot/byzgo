# Ready to upload — Google Play (BytzGo)

Account: **jerryanthony61@gmail.com**

## Admin on the web (Render)

**https://www.bytzgo.net/admin** — administrators only. See [RENDER_ADMIN_WEB.md](./RENDER_ADMIN_WEB.md).

## 1. Upload this file

```
mobile\build\app\outputs\bundle\release\app-release.aab
```

Package: **`net.bytzgo.app`** · Version: **1.0.1 (2)** — rebuild AAB after pulling latest `main`

## 2. Play Console URLs

| Step | URL / value |
|------|-------------|
| Console | https://play.google.com/console |
| Privacy policy | https://www.bytzgo.net/privacy |
| Account deletion | https://www.bytzgo.net/account-deletion |
| Contact email | jerryanthony61@gmail.com |
| Listing text | [PLAY_STORE_LISTING.md](./PLAY_STORE_LISTING.md) |
| Data safety | [PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md) |

## 3. Google Sign-In on Play builds (required once)

Open [Firebase bytzgo-9bd89](https://console.firebase.google.com/project/bytzgo-9bd89/settings/general) → Android **`net.bytzgo.app`**:

1. **Upload key** SHA-1: `B2:A0:44:C8:79:A5:97:50:95:AB:9A:C5:B6:0A:2F:FD:7C:DE:3F:2D` (local release keystore)
2. **Play App Signing key** SHA-1: Play Console → **Setup** → **App signing** → copy **App signing key certificate** SHA-1 → add the same fingerprint in Firebase.

Or run: `npm run setup:firebase:android` (uses `backend/firebase-service-account.json`).

Then build a new bundle (repo bakes production API + Google client):

```powershell
npm run flutter:build:aab
```

Details: [GOOGLE_CLOUD_PLAY_SHA.md](./GOOGLE_CLOUD_PLAY_SHA.md)

## 4. Validate before upload

```powershell
npm run play:validate
```

## 5. Recommended first track

**Internal testing** → add your Gmail as tester → install → test login, map, rider Online, push.

Then promote to **Production**.
