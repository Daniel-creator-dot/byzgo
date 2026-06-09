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

### CLI (optional)

```bash
cd mobile
./scripts/build_app_store_ipa.sh
```

Requires the same Apple ID in Xcode (automatic signing). Output: `build/ios/ipa/*.ipa` — upload with **Transporter** or Organizer.

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
