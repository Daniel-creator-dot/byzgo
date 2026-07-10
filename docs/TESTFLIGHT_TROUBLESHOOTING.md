# TestFlight — build not showing

## Where to look (most common mistake)

Builds do **not** appear under **App Store → Version**.

1. [App Store Connect → BytzGo → TestFlight](https://appstoreconnect.apple.com/apps/6774963354/testflight/ios)
2. Left sidebar: **iOS**
3. Check two sections:
   - **Build Uploads** — upload/processing status (Processing → Complete / Failed)
   - **Builds** (under version **1.0.51**) — ready for testing after processing

Build **72** was uploaded successfully at ~05:09 UTC. Apple usually needs **15–60 minutes** to process.

## If Build Uploads shows nothing

### 1. Accept agreements (required)

Your account reported **Agreements: []** and **Is Signup Complete: NO**.

Open [Agreements, Tax, and Banking](https://appstoreconnect.apple.com/agreements) and accept:

- **Apple Developer Program License Agreement** (if pending)
- **Paid Applications Agreement** (required even for free apps / TestFlight)

Until this is done, uploads can succeed but builds may never become available for testing.

### 2. Check email

Apple emails **jerryanthony61@gmail.com** when a build:

- Starts processing
- **Fails** (missing compliance, invalid entitlements, etc.)
- Is **Ready to Test**

Search for mail from **App Store Connect** or **Apple Developer**.

### 3. Export compliance (yellow warning)

If build **72** appears with a yellow **Missing Compliance** icon:

1. TestFlight → iOS → build **72**
2. Click **Manage** or **Provide Export Compliance**
3. Answer: app uses only standard HTTPS → **No** custom encryption  
   (Info.plist already has `ITSAppUsesNonExemptEncryption = false`)

### 4. Add build to Internal Testing

Processing alone is not enough for the TestFlight app on your phone:

1. TestFlight → **Internal Testing** → create/select a group (e.g. "Team")
2. Click **+** and add build **72**
3. Ensure your Apple ID is an **internal tester** (Users and Access → your account → Apps → BytzGo)

### 5. On your iPhone

1. Install **TestFlight** from the App Store
2. Sign in with the same Apple ID as App Store Connect
3. Open the invite or the BytzGo TestFlight page
4. Tap **Install**

## App Store version 1.0.51

Live App Store version is still **1.0.50**. To submit **72** for App Review:

1. App Store → **+ Version** → **1.0.51**
2. After build **72** shows **Ready to Submit**, select it under **Build**
3. Paste notes from `mobile/app_store_whats_new_1.0.51.txt`

## Re-upload if build failed

```bash
cd mobile
./scripts/manual_sign_app_store_ipa.sh
./scripts/upload_app_store_ipa.sh
```

## Quick links

| Page | URL |
|------|-----|
| TestFlight (BytzGo) | https://appstoreconnect.apple.com/apps/6774963354/testflight/ios |
| Agreements | https://appstoreconnect.apple.com/agreements |
| Users & Access | https://appstoreconnect.apple.com/access/users |
