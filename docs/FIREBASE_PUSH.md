# Firebase push notifications (FCM)

Riders receive **incoming job alerts when the app is closed or the screen is off** after FCM is configured.

## One-time setup

1. Open [Firebase Console](https://console.firebase.google.com/) → project **bytzgo-72f1c**.
2. Add an **Android app** with package name `com.bytzgo.bytzgo_mobile`.
3. Download `google-services.json` into `mobile/android/app/google-services.json`.
4. Run from `mobile/`:

   ```bash
   flutterfire configure
   ```

   Or build the APK with dart-defines (from Firebase app settings):

   ```bash
   flutter build apk --release \
     --dart-define=API_URL=https://www.bytzgo.net \
     --dart-define=FIREBASE_API_KEY=your_api_key \
     --dart-define=FIREBASE_APP_ID=1:xxx:android:xxx \
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx
   ```

5. On the phone: **Settings → Apps → BytzGo → Notifications** → allow.
6. Rider: go **Online** once so the app registers the FCM token with the API.

## Backend

The API stores tokens in `fcm_tokens` and sends high-priority FCM when dispatching rides (alongside web push for the PWA).

Ensure the Firebase **service account** JSON is on Render (`bytzgo-72f1c-firebase-adminsdk-*.json`) so `firebase-admin` can send messages.

## In-app call

Trip **Call** opens a full-screen in-app UI, then connects via the phone dialer. True VoIP (no phone number) would need Twilio/Agora in a later phase.
