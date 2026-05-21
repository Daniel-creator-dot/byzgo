import 'package:flutter/foundation.dart' show kReleaseMode;

import 'maps_key.dart';

/// Runtime configuration via `--dart-define` or repo `.env.local` (see mobile/README.md).
class Env {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: kReleaseMode
        ? 'https://www.bytzgo.net'
        : 'http://10.0.2.2:3000',
  );
  /// OAuth web client ID for Google Sign-In (public; override via --dart-define).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '568487483843-99c0bucqujokf2h1vtmno1ku0jea7b4f.apps.googleusercontent.com',
  );

  /// Render redirects apex → www; Dio fails on 307 for POST unless we use www directly.
  static String get apiBaseUrl {
    var url = apiUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host == 'bytzgo.net') {
      return uri.replace(host: 'www.bytzgo.net').toString();
    }
    return url;
  }

  static bool get isGoogleSignInEnabled =>
      googleWebClientId.trim().contains('.apps.googleusercontent.com');

  /// Google Maps key — dart-define, then [MapsKey.resolved] from sync script.
  static String get googleMapsApiKey {
    const fromDefine = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    return MapsKey.resolved.trim();
  }

  static bool get hasGoogleMaps {
    final k = googleMapsApiKey;
    return k.length >= 20 && k.startsWith('AIza');
  }
}
