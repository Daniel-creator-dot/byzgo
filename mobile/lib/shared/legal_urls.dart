import '../core/env.dart';

/// Legal pages served by the API (see backend/legal/).
class LegalUrls {
  static String get _origin {
    final base = Env.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    return base;
  }

  static String get privacy => '$_origin/privacy';
  static String get terms => '$_origin/terms';
  static String get accountDeletion => '$_origin/account-deletion';
}
