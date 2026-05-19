import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// Initializes Firebase when [DefaultFirebaseOptions] is configured.
/// Email/password login works without this.
Future<void> bootstrapFirebase() async {
  if (!DefaultFirebaseOptions.isConfigured) {
    debugPrint('BytzGo: Firebase skipped (email login still works)');
    return;
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('BytzGo: Firebase initialized');
  } catch (e, st) {
    debugPrint('BytzGo: Firebase init failed: $e\n$st');
  }
}
