import 'package:flutter/foundation.dart' show kReleaseMode;

import 'maps_key.dart';
import 'oauth_config.dart';

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
    defaultValue: kGoogleWebClientId,
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

  /// Google Sign-In disabled in product until re-enabled explicitly.
  static bool get isGoogleSignInEnabled => false;

  static String? _runtimeMapsApiKey;

  /// Set after [/api/config/maps] when the APK was built without a baked-in key.
  static void setRuntimeMapsApiKey(String? key) {
    final t = key?.trim() ?? '';
    _runtimeMapsApiKey = t.isNotEmpty ? t : null;
  }

  /// Google Maps key — dart-define, sync script, then runtime config from API.
  static String get googleMapsApiKey {
    final runtime = _runtimeMapsApiKey;
    if (runtime != null && runtime.isNotEmpty) return runtime;
    const fromDefine = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    return MapsKey.resolved.trim();
  }

  static bool get hasGoogleMaps {
    final k = googleMapsApiKey;
    return k.length >= 20 && k.startsWith('AIza');
  }
}
