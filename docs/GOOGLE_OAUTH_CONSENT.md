# Google Sign-In — show “BytzGo” (not `project-645977332644`)

## Why you still see `project-645977332644` after fixing Firebase

**Firebase Console ≠ OAuth consent branding.**

| Where you edited yesterday | What it affects |
|----------------------------|-----------------|
| Firebase → **Project settings → General → Public-facing name** | Firebase console UI only |
| Firebase → **Authentication → Google** toggle | Enables the provider; does **not** set the sign-in sheet title |
| **Google Cloud → OAuth consent / Auth Platform → Branding** | What users see on `accounts.google.com` |

If you set **App name = BytzGo** in Cloud Console but the simulator still shows `project-645977332644`, Google is almost always showing **unverified / draft** branding. Per [Google’s branding rules](https://support.google.com/cloud/answer/10311615), the **custom app name on the consent screen only appears after brand verification is approved** (or is in **Published** state). Until then, Google falls back to **`project-{project_number}`** — here `645977332644` for **`bytzgo-9bd89`**.

---

## Fix (Firebase → same GCP project)

### 1. Open branding from Firebase (correct project)

1. [Firebase Console → bytzgo-9bd89](https://console.firebase.google.com/project/bytzgo-9bd89/settings/general)
2. Confirm **Project ID** = `bytzgo-9bd89` and **Project number** = `645977332644`.
3. Use **“Open in Google Cloud Console”** (or **Project settings → Integrations → Google Cloud**).
4. Go to **[Auth Platform → Branding](https://console.cloud.google.com/auth/branding?project=bytzgo-9bd89)** (not only the old “OAuth consent screen” menu).

### 2. Fill branding (required for verification)

| Field | Suggested value |
|--------|------------------|
| **App name** | `BytzGo` |
| **User support email** | Your support inbox |
| **App home page** | `https://www.bytzgo.net` |
| **Privacy policy** | `https://www.bytzgo.net/privacy` |
| **Terms of service** (if asked) | `https://www.bytzgo.net/terms` or same as privacy host |
| **Authorized domains** | `bytzgo.net`, `www.bytzgo.net` (add in Branding / consent screen) |
| **Logo** (optional) | Square BytzGo icon |

Click **Save**.

### 3. Submit brand verification (this is the step that makes the name appear)

1. On the same **Branding** page, check status:
   - **Draft** → users still see `project-645977332644`
   - **Published** / **Verified** → users should see **BytzGo**
2. If there is **Submit for verification** / **Publish branding**, submit and complete any domain checks (Search Console for `bytzgo.net` if requested).
3. Wait for Google email (often **1–7 days**; sometimes faster for light brand-only verification).

Direct links:

- [Branding](https://console.cloud.google.com/auth/branding?project=bytzgo-9bd89)
- [Verification center](https://console.cloud.google.com/auth/verification?project=bytzgo-9bd89)

### 4. After approval

- Sign **out** of Google on the simulator (or use another test account).
- Run the app again and tap **Continue with Google**.
- Title should read **“You’re signing back in to BytzGo”**.

---

## Also check in Firebase (iOS app identity)

Your Android `google-services.json` still lists an iOS OAuth client with bundle **`com.example.bytzgo`**, while the shipped app uses **`com.bytzgo.bytzgoMobile`** (`GoogleService-Info.plist`). That mismatch does not cause the `project-…` label, but it can break sign-in on some builds.

1. Firebase → **Project settings → Your apps** → iOS app **`com.bytzgo.bytzgoMobile`** (add if missing).
2. Download a fresh **`GoogleService-Info.plist`** into `mobile/ios/Runner/`.
3. Re-download **`google-services.json`** after iOS app is correct (or run `node backend/scripts/setup-firebase-android.mjs` if you have `backend/firebase-service-account.json`).

---

## What does *not* fix the name

- Login copy in Flutter / React
- `GOOGLE_WEB_CLIENT_ID` in code
- Render deploy
- Only renaming the Firebase project display name

## Production API (separate)

Google Sign-In on the server requires Render env:

`GOOGLE_SIGN_IN_ENABLED=true`

(plus existing `GOOGLE_WEB_CLIENT_ID`). Without it, the app may open Google but `POST /api/auth/google` returns **403**.
