import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/push_notification_service.dart';
import 'firebase_bootstrap.dart';

/// Entry point for BytzGo mobile.
///
/// Run with your API URL, e.g.:
/// `flutter run --dart-define=API_URL=http://10.0.2.2:3000`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    debugPrint('BytzGo API: ${Env.apiBaseUrl}');
  }
  try {
    await bootstrapFirebase();
  } catch (e, st) {
    debugPrint('BytzGo Firebase bootstrap failed: $e\n$st');
  }
  try {
    await PushNotificationService.instance.initialize();
  } catch (e, st) {
    debugPrint('BytzGo push init failed at startup: $e\n$st');
  }
  runApp(const BytzGoApp());
}
