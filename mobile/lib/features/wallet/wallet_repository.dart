import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';

class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;

  Future<double> withdraw(double amount) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/wallet/withdraw',
      data: {'amount': amount},
    );
    return parseJsonDoubleOrZero(res.data?['balance']);
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Withdrawal failed');
    }
    return err.toString();
  }
}
