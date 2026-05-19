import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/env.dart';
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
  await bootstrapFirebase();
  runApp(const BytzGoApp());
}
