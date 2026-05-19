import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';

class PaystackCheckoutSession {
  const PaystackCheckoutSession({
    required this.reference,
    required this.authorizationUrl,
    required this.amountGhs,
  });

  final String reference;
  final String authorizationUrl;
  final double amountGhs;
}

class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;

  Future<PaystackCheckoutSession> initializeTopup(double amountGhs) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/wallet/topup/initialize',
      data: {'amount': amountGhs},
    );
    final data = res.data;
    if (data == null) {
      throw Exception('Could not start Paystack checkout');
    }
    final url = data['authorization_url']?.toString().trim() ?? '';
    final reference = data['reference']?.toString().trim() ?? '';
    if (url.isEmpty || reference.isEmpty) {
      throw Exception('Paystack checkout URL missing from server');
    }
    final amount = double.tryParse(data['amount']?.toString() ?? '') ?? amountGhs;
    return PaystackCheckoutSession(
      reference: reference,
      authorizationUrl: url,
      amountGhs: amount,
    );
  }

  Future<double> fetchBalance() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/wallet');
    return parseJsonDoubleOrZero(res.data?['balance']);
  }

  Future<double> creditTopup(String reference) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/wallet/topup',
      data: {'reference': reference.trim()},
    );
    return parseJsonDoubleOrZero(res.data?['balance']);
  }

  Future<double> withdraw({
    required double amount,
    String? phone,
    String method = 'momo',
    String network = 'mtn',
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/wallet/withdraw',
      data: {
        'amount': amount,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'method': method,
        'network': network,
      },
    );
    return parseJsonDoubleOrZero(res.data?['balance']);
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Wallet request failed');
    }
    return err.toString();
  }

}
