google-services.json must match applicationId "net.bytzgo.app".

If FCM or Google Sign-In fails after a package change:
1. Firebase Console -> bytzgo-9bd89 -> Add Android app -> net.bytzgo.app
2. Download a NEW google-services.json (new mobilesdk_app_id)
3. Update mobile/lib/firebase_options.dart android appId from that file
4. Add release SHA-1 from scripts/print_release_sha1.ps1

See docs/FIREBASE_ANDROID_PACKAGE.md
