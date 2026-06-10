# Firebase push — iOS (lock-screen rider job alerts)

Riders only get **Uber/Bolt-style alerts when the screen is off** if all three layers work:

1. **Firebase** can reach Apple (APNs key uploaded)
2. **Backend** sends FCM with iOS alert + sound (`fcm: true` on `/api/health`)
3. **iPhone** has build **1.0.46+**, notifications allowed, rider **Online**

## Step 1 — Upload APNs key to Firebase (one-time)

Without this step, **no iOS push will ever arrive**, even if Android works.

1. [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list) → **+**
   - Name: `BytzGo APNs`
   - Enable **Apple Push Notifications service (APNs)**
   - Download **AuthKey_XXXXXXXXXX.p8** (only once)
   - Note **Key ID** (10 characters)

2. [Firebase Console](https://console.firebase.google.com/project/bytzgo-9bd89/settings/cloudmessaging) → **Project settings** → **Cloud Messaging**

3. Under **Apple app configuration** (app `com.bytzgo.bytzgoMobile`):
   - Upload the **.p8** file
   - **Key ID** from step 1
   - **Team ID:** `MHTN5HYAHW`

4. Save. No app rebuild needed for this step alone.

## Step 2 — Deploy backend

Production must show `"fcm": true`:

```bash
curl -s https://www.bytzgo.net/api/health | jq .fcm
```

Push latest `main` so Render redeploys (incoming-ride iOS APNs payload + test endpoints).

## Step 3 — Install iOS build 1.0.46+

App Store **1.0.44** does not include the latest push fixes. Install **1.0.46 (57)** or newer from TestFlight/App Store after upload.

On the iPhone:

1. **Settings → BytzGo → Notifications** → Allow Notifications, Sounds, Banners
2. Optional: enable **Time Sensitive Notifications** for BytzGo
3. Open BytzGo → log in as **rider** → tap **Go Online**
4. Wait ~5 seconds (FCM token registers)

## Step 4 — Test with screen locked

### Option A — API test (fastest)

While rider is **Online**, lock the phone, then from a computer (use rider JWT):

```bash
curl -s -X POST https://www.bytzgo.net/api/push/test-incoming-ride \
  -H "Authorization: Bearer RIDER_JWT_HERE"
```

Expected: banner + sound within a few seconds.

Check token is saved:

```bash
curl -s https://www.bytzgo.net/api/push/status \
  -H "Authorization: Bearer RIDER_JWT_HERE"
```

Should show `{ "fcmEnabled": true, "tokens": [{ "platform": "ios", ... }] }`.

### Option B — Real delivery

1. Rider **Online**, phone locked
2. Customer creates a delivery nearby
3. Rider should get **New delivery job** alert

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `tokens: []` on `/api/push/status` | Reinstall app; allow notifications; go **Online** |
| `platform: "android"` on iPhone | Update to 1.0.46+; go Online again |
| `fcmEnabled: false` | Add Firebase service account on Render — see [FIREBASE_PUSH.md](./FIREBASE_PUSH.md) |
| Test returns OK but no alert | **APNs .p8 not in Firebase** (Step 1) |
| Alert but no sound | iPhone mute switch; Settings → Sounds; enable notification sounds |
| Works in app only | Old build or missing APNs key — not a code bug on device |

## Render logs

After a real job offer, logs should show:

```
[push] incoming-ride → 1 rider(s), 1 FCM token(s) (1 iOS)
```

If you see `FCM failed` with `messaging/third-party-auth-error`, the APNs key in Firebase is wrong or missing.
