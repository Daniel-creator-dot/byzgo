# Play Store UI & quality checklist — BytzGo mobile

Use before uploading `app-release.aab`.

## In-app polish (repo)

- [x] Splash capped ~0.9s min + branded native splash logo
- [x] System chrome (status/nav) for map vs light tabs
- [x] 48dp header/nav touch targets + semantics on primary CTAs
- [x] Route transitions (fade) between login and role homes
- [x] Branded route error screen (`/admin` typos, deep links)
- [x] Shared empty + error panels (retry, icons)
- [x] Profile: legal links + account deletion URL
- [x] Profile rows explain PIN / notifications (no dead taps)
- [x] Sign-out confirmation (customer + rider)
- [x] Reduced-motion friendly launch carousel
- [x] Maps/Places errors surfaced (search, GPS, checkout)
- [x] Ghana-only GPS and delivery addresses (no silent Accra fallback abroad)
- [x] Shops without lat/lng geocoded from name + address
- [x] Release builds default API to `https://www.bytzgo.net`

## Play Console (you)

- [ ] 2+ phone screenshots (customer book, live track, rider drive)
- [ ] Feature graphic 1024×500
- [ ] Icon 512×512 matches launcher
- [ ] Data safety form ([PLAY_STORE_DATA_SAFETY.md](./PLAY_STORE_DATA_SAFETY.md))
- [ ] Privacy + Terms URLs load on device browser
- [ ] Account deletion: in-app button + https://www.bytzgo.net/account-deletion

## Test on a real device

1. Cold start → splash → login under 3s total feel
2. Customer: book trip, track, shop checkout (GPS + address search in Ghana)
3. Customer: pick shop without map pin — should still open menu/checkout
4. Customer: activity tab empty + error (airplane mode → retry)
5. Rider: go online, empty active/history states
6. Profile: open Privacy, Terms, Account deletion
7. Sign out → confirm dialog → login again

## Build

```powershell
npm run flutter:build:aab
cd mobile
.\scripts\validate_play_release.ps1
```
