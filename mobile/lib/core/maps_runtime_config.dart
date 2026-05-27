import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'env.dart';

/// Fetches Maps SDK key from backend when not baked in at build time.
class MapsRuntimeConfig extends ChangeNotifier {
  MapsRuntimeConfig(this._api);

  final ApiClient _api;
  bool _loaded = false;
  bool _loading = false;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading || Env.hasGoogleMaps) {
      _loaded = true;
      return;
    }
    _loading = true;
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/api/config/maps');
      final key = res.data?['apiKey']?.toString().trim() ?? '';
      if (key.length >= 20 && key.startsWith('AIza')) {
        Env.setRuntimeMapsApiKey(key);
        notifyListeners();
      }
    } catch (_) {
      /* maps stay unavailable */
    } finally {
      _loading = false;
      _loaded = true;
    }
  }
}
