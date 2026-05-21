# Play Store UI & quality checklist — BytzGo mobile

Use before uploading `app-release.aab`.

## In-app polish (repo)

- [x] Splash capped ~1.4s (not 4s+)
- [x] Branded route error screen (`/admin` typos, deep links)
- [x] Shared empty + error panels (retry, icons)
- [x] Profile: legal links + account deletion URL
- [x] Profile rows explain PIN / notifications (no dead taps)
- [x] Sign-out confirmation (customer + rider)
- [x] Reduced-motion friendly launch carousel

## Play Console (you)

- [ ] 2+ phone screenshots (customer book, live track, rider drive)
- [ ] Feature graphic 1024×500
- [ ] Icon 512×512 matches launcher
- [ ] Data safety form ([PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md))
- [ ] Privacy + Terms URLs load on device browser
- [ ] Account deletion: in-app button + https://www.bytzgo.net/account-deletion

## Test on a real device

1. Cold start → splash → login under 3s total feel
2. Customer: book trip, track, activity tab empty + error (airplane mode → retry)
3. Rider: go online, empty active/history states
4. Profile: open Privacy, Terms, Account deletion
5. Sign out → confirm dialog → login again

## Build

```powershell
npm run flutter:build:aab
cd mobile
.\scripts\validate_play_release.ps1
```
