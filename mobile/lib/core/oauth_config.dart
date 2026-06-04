/// Firebase Web OAuth client (type 3 in google-services.json) for Google Sign-In.
/// Must match Render `GOOGLE_WEB_CLIENT_ID` and Play release builds.
/// Passed as [GoogleSignIn.serverClientId] on Android (required for ID token).
const kGoogleWebClientId =
    '645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com';

/// Android OAuth client (type 1 in android/app/google-services.json).
/// Do not pass to [GoogleSignIn.clientId] on Android — the plugin reads google-services.json.
const kGoogleAndroidClientId =
    '645977332644-rv482i78e7hln0u3dh475dn4g0rgoa2l.apps.googleusercontent.com';

/// iOS OAuth client from `ios/Runner/GoogleService-Info.plist` (CLIENT_ID).
const kGoogleIosClientId =
    '645977332644-7r6hmbj6sklvrv96l2i312c34i1kgn4u.apps.googleusercontent.com';

/// URL scheme for Google Sign-In redirect (`REVERSED_CLIENT_ID` in plist).
const kGoogleIosUrlScheme =
    'com.googleusercontent.apps.645977332644-7r6hmbj6sklvrv96l2i312c34i1kgn4u';
