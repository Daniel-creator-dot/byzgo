import 'maps_key.dart';

/// Runtime configuration via `--dart-define` or repo `.env.local` (see mobile/README.md).
class Env {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// OAuth web client ID for Google Sign-In (required for Google button).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static String get apiBaseUrl => apiUrl.replaceAll(RegExp(r'/$'), '');

  static bool get isGoogleSignInEnabled => googleWebClientId.trim().isNotEmpty;

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
