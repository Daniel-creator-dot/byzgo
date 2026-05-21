# Ready to upload — Google Play (BytzGo)

Account: **jerryanthony61@gmail.com**

## 1. Upload this file

```
mobile\build\app\outputs\bundle\release\app-release.aab
```

Package: **`net.bytzgo.app`** · Version: **1.0.0 (1)**

## 2. Play Console URLs

| Step | URL / value |
|------|-------------|
| Console | https://play.google.com/console |
| Privacy policy | https://www.bytzgo.net/privacy |
| Account deletion | https://www.bytzgo.net/account-deletion |
| Contact email | jerryanthony61@gmail.com |
| Listing text | [PLAY_STORE_LISTING.md](./PLAY_STORE_LISTING.md) |
| Data safety | [PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md) |

## 3. One Firebase step (if push or Google Sign-In fails on Play build)

Open [Firebase bytzgo-9bd89](https://console.firebase.google.com/project/bytzgo-9bd89/settings/general):

1. **Add app** → Android → package **`net.bytzgo.app`** (skip if already listed).
2. **Add fingerprint** → SHA-1: `B2:A0:44:C8:79:A5:97:50:95:AB:9A:C5:B6:0A:2F:FD:7C:DE:3F:2D`
3. Download **google-services.json** → replace `mobile/android/app/google-services.json` → run `npm run flutter:build:aab` again.

Details: [GOOGLE_CLOUD_PLAY_SHA.md](./GOOGLE_CLOUD_PLAY_SHA.md)

## 4. Validate before upload

```powershell
npm run play:validate
```

## 5. Recommended first track

**Internal testing** → add your Gmail as tester → install → test login, map, rider Online, push.

Then promote to **Production**.
