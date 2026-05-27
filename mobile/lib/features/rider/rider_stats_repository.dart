import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/rider_stats.dart';

class RiderStatsRepository {
  RiderStatsRepository(this._api);

  final ApiClient _api;

  Future<RiderStats> fetchStats() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/rider/stats');
    final data = res.data;
    if (data == null) throw Exception('Empty rider stats response');
    return RiderStats.fromJson(Map<String, dynamic>.from(data));
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Could not load driver stats');
    }
    return err.toString();
  }
}
