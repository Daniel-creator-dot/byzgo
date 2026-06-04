# BytzGo — Apple App Store (iOS)

## App identity

| Field | Value |
|--------|--------|
| App name | BytzGo |
| Bundle ID | `com.bytzgo.bytzgoMobile` |
| Version | From `mobile/pubspec.yaml` (e.g. `1.0.43+51` → marketing **1.0.43**, build **51**) |

## One-time Mac setup

1. Install Xcode, Flutter, CocoaPods.
2. In Firebase Console (project **bytzgo-9bd89**), register an **iOS app** with bundle ID **`com.bytzgo.bytzgoMobile`**.
3. Download **GoogleService-Info.plist** → replace `mobile/ios/Runner/GoogleService-Info.plist`.
4. Enable **Maps SDK for iOS** and **Push Notifications** in Google Cloud / Firebase.
5. In Apple Developer: create App ID, enable Push Notifications, create distribution certificate & provisioning profile.
6. In Xcode → **Runner** target → **Signing & Capabilities**: select your **Team**.

## Maps API key (required for map)

From repo root with `.env.local` containing `GOOGLE_MAPS_API_KEY`:

```powershell
cd mobile
.\scripts\sync_maps_key.ps1
```

This writes `ios/Runner/MapsConfig.plist` and `lib/core/maps_key.dart`. Restrict the key to iOS app `com.bytzgo.bytzgoMobile` in Google Cloud.

## Build for TestFlight / App Store

```bash
cd mobile
chmod +x scripts/build_app_store_ipa.sh
./scripts/build_app_store_ipa.sh
```

If signing fails (no Apple ID in Xcode):

```bash
./scripts/build_app_store_ipa.sh --open-xcode
```

Then **Product → Archive → Distribute App → App Store Connect**.

Output: `build/ios/ipa/*.ipa` — upload with **Transporter** or Xcode Organizer.

## Pre-submit checklist

Run:

```bash
./mobile/scripts/validate_app_store.sh
```

App Store Connect:

- **Privacy Policy URL:** https://www.bytzgo.net/privacy  
- **Terms:** https://www.bytzgo.net/terms  
- **Account deletion:** https://www.bytzgo.net/account-deletion (in-app: Profile → Delete account)  
- **Export compliance:** Standard encryption only (HTTPS) — `ITSAppUsesNonExemptEncryption` = false in Info.plist  
- **Category:** Navigation or Food & Drink (delivery)  
- **Screenshots:** iPhone 6.7" (1284×2778) — see `mobile/app_store_screenshots/iphone/` and `mobile/scripts/capture_app_store_screenshots.sh`  
- **Sign in with Google** visible on login (iPad + iPhone); **Apple Maps** option for rider navigation  
- **Google OAuth branding:** App name **BytzGo** verified in Cloud Console (not `project-645977332644`) — see `docs/GOOGLE_OAUTH_CONSENT.md`  

## Test on simulator

```bash
cd mobile
./scripts/setup_ios_xcode.sh
```

Pick iPhone simulator → Run (⌘R).

## Rider push (production)

Upload APNs key (.p8) in Firebase → Cloud Messaging → Apple app configuration.

Without this, rider incoming-job alerts work in-app when online but not when the app is fully closed.
