import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/admin_overview.dart';
import '../../models/rider_document.dart';

class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<AdminOverview> fetchOverview() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/admin/overview');
    return AdminOverview.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<Map<String, dynamic>> fetchRevenue() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/admin/revenue');
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<PendingRiderApplication>> fetchPendingRiders() async {
    final res = await _api.dio.get<List<dynamic>>('/api/admin/pending-riders');
    final data = res.data ?? [];
    return data
        .whereType<Map>()
        .map((e) => PendingRiderApplication.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> approveRider(String id) async {
    await _api.dio.patch<Map<String, dynamic>>('/api/admin/riders/$id/approve');
  }

  Future<void> rejectRider(String id, {String? reason}) async {
    await _api.dio.patch<Map<String, dynamic>>(
      '/api/admin/riders/$id/reject',
      data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Admin request failed');
    }
    return err.toString();
  }
}
