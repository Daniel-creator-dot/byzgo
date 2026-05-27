import 'package:dio/dio.dart';

import '../shared/delivery_pricing.dart';
import 'api_client.dart';

class ConfigRepository {
  ConfigRepository(this._api);

  final ApiClient _api;

  Future<String> fetchPaystackPublicKey() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/config/paystack');
    return res.data?['publicKey']?.toString().trim() ?? '';
  }

  Future<Map<String, dynamic>> fetchPricingPayload() async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/api/config/pricing',
      options: Options(
        headers: {'Cache-Control': 'no-cache'},
      ),
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<double> fetchPricePerKm() async {
    try {
      final data = await fetchPricingPayload();
      final raw = data['price_per_km'];
      final n = double.tryParse(raw?.toString() ?? '') ?? defaultDeliveryPricePerKm;
      return n > 0 ? n : defaultDeliveryPricePerKm;
    } catch (_) {
      return defaultDeliveryPricePerKm;
    }
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Could not load settings');
    }
    return err.toString();
  }
}
