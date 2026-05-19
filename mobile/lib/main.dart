import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_bootstrap.dart';

/// Entry point for BytzGo mobile.
///
/// Run with your API URL, e.g.:
/// `flutter run --dart-define=API_URL=http://10.0.2.2:3000`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapFirebase();
  runApp(const BytzGoApp());
}
