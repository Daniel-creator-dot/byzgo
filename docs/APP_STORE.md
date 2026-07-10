# BytzGo — Apple App Store (iOS)

## App identity

| Field | Value |
|--------|--------|
| App name | BytzGo |
| Bundle ID | `com.bytzgo.bytzgoMobile` |
| Version | From `mobile/pubspec.yaml` (current **1.0.51+71** → marketing **1.0.51**, build **71**) |

## One-time Mac setup

1. Install Xcode, Flutter, CocoaPods.
2. In Firebase Console (project **bytzgo-9bd89**), register an **iOS app** with bundle ID **`com.bytzgo.bytzgoMobile`**.
3. Download **GoogleService-Info.plist** → replace `mobile/ios/Runner/GoogleService-Info.plist`.
4. Enable **Maps SDK for iOS** and **Push Notifications** in Google Cloud / Firebase.
5. In Apple Developer: create App ID, enable **Push Notifications** and **Sign in with Apple**, create distribution certificate & App Store provisioning profile.
6. In Xcode → **Runner** target → **Signing & Capabilities**: select your **Team**, add **Sign in with Apple** if missing.
7. After enabling Sign in with Apple on the App ID, **regenerate** the App Store profile (Xcode → Settings → Accounts → Download Manual Profiles, or Developer portal → Profiles → Edit → Save).

## Maps API key (required for map)

From repo root with `.env.local` containing `GOOGLE_MAPS_API_KEY`:

```powershell
cd mobile
.\scripts\sync_maps_key.ps1
```

This writes `ios/Runner/MapsConfig.plist` and `lib/core/maps_key.dart`. Restrict the key to iOS app `com.bytzgo.bytzgoMobile` in Google Cloud.

## Build for TestFlight / App Store

### Recommended: Archive in Xcode

1. Open **`mobile/ios/Runner.xcworkspace`** (not `.xcodeproj`).
2. **Xcode → Settings → Accounts** — sign in with the Apple ID for team **MHTN5HYAHW**.
3. Select the **Runner** target → **Signing & Capabilities**:
   - **Team:** jeremiah anthony amissah (`MHTN5HYAHW`)
   - **Automatically manage signing:** ON (Release uses `Runner.Release.entitlements` with **production** push).
4. Scheme **Runner**, destination **Any iOS Device (arm64)** (not a simulator).
5. From Terminal once (maps key + Flutter deps):

   ```bash
   cd mobile
   flutter pub get
   ```

6. In Xcode: **Product → Archive**.
7. **Organizer → Distribute App → App Store Connect → Upload**.

If archive fails on push: enable **Push Notifications** on the App ID at [developer.apple.com](https://developer.apple.com/account/resources/identifiers), then let Xcode refresh profiles (or download a new **App Store** profile and set Manual signing).

### CLI (recommended on this Mac)

```bash
cd mobile
./scripts/manual_sign_app_store_ipa.sh
# or
./scripts/upload_now.sh
```

Uses local Distribution cert + App Store profile (no Apple ID in Xcode required). Output: `build/ios/ipa/BytzGo.ipa` — upload with **Transporter**.

Auto-upload (optional): set `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` in repo-root `.env.local`, then `./scripts/upload_app_store_ipa.sh`.

## What's New (App Store Connect — v1.0.51)

Copy from `mobile/app_store_whats_new_1.0.51.txt` when submitting build **71**.

Highlights:

- **Faster dispatch** — riders receive ride offers sooner
- **Improved real-time updates** when the app is in the background
- **Driver wallet / commission** improvements
- **API performance** for Ghana (EU-hosted backend)

## What's New (App Store Connect — v1.0.50)

Copy from `mobile/app_store_whats_new_1.0.50.txt` when submitting build **69**.

Highlights for this release:

- **Okada & Keke** passenger rides (motorcycle taxi + tricycle)
- **Package delivery** with tiered per-km pricing
- **Driver signup** — choose Okada, Keke, or Bicycle
- **Dispatch matching** by rider vehicle type
- **Admin KYC** shows registered vehicle type

## What's New (App Store Connect — v1.0.45)

Copy from `mobile/app_store_whats_new_1.0.45.txt` when submitting build **54**.

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
- **Sign in with Google** visible on login (iPad + iPhone); **Sign in with Apple** on iOS
- **Driver signup** includes vehicle type picker (Okada / Keke / Bicycle) before Apple or Google sign-up
- **Google OAuth branding:** App name **BytzGo** verified in Cloud Console (not `project-645977332644`) — see `docs/GOOGLE_OAUTH_CONSENT.md`  

## CI / TestFlight (GitHub Actions)

On a Mac or via GitHub Actions (`.github/workflows/ios-testflight.yml`):

1. Add repository secrets (Settings → Secrets → Actions):
   - `APPLE_CERTIFICATE_BASE64` — Distribution `.p12` (base64)
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_PROVISIONING_PROFILE_BASE64` — App Store profile for `com.bytzgo.bytzgoMobile`
   - `KEYCHAIN_PASSWORD` — any strong random string for the CI keychain
   - `APPLE_ID` — Apple Developer account email
   - `APPLE_APP_SPECIFIC_PASSWORD` — from [account.apple.com](https://account.apple.com) → App-Specific Passwords
2. Run workflow **iOS TestFlight** (manual dispatch) on `main`.
3. In App Store Connect, attach build **69** to version **1.0.50** and paste release notes from `app_store_whats_new_1.0.50.txt`.

iOS build metadata (no IPA hosted): `GET https://www.bytzgo.net/download/ios/version`

## Test on simulator

```bash
cd mobile
./scripts/setup_ios_xcode.sh
```

Pick iPhone simulator → Run (⌘R).

## Rider push (production)

Upload APNs key (.p8) in Firebase → Cloud Messaging → Apple app configuration.

Without this, rider incoming-job alerts work in-app when online but not when the app is fully closed.
