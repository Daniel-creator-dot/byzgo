import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/admin_overview.dart';
import '../../models/admin_pricing_settings.dart';
import '../../models/delivery_zone.dart';
import '../../models/admin_pending_product.dart';
import '../../models/admin_vendor.dart';
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

  Future<AdminPricingSettings> fetchPricingSettings() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/admin/settings');
    return AdminPricingSettings.fromJson(
      Map<String, dynamic>.from(res.data ?? {}),
    );
  }

  Future<void> savePricingSettings(AdminPricingSettings settings) async {
    await _api.dio.patch<Map<String, dynamic>>(
      '/api/admin/settings',
      data: settings.toPatchBody(),
    );
  }

  Future<List<DeliveryZone>> fetchDeliveryZones() async {
    final res = await _api.dio.get<List<dynamic>>('/api/delivery-zones');
    final data = res.data ?? [];
    return data
        .whereType<Map>()
        .map((e) => DeliveryZone.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DeliveryZone> createDeliveryZone(
    DeliveryZone zone, {
    required double globalRatePerKm,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/delivery-zones',
      data: zone.toCreateBody(globalRatePerKm: globalRatePerKm),
    );
    return DeliveryZone.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<DeliveryZone> updateDeliveryZone(
    String id,
    DeliveryZone zone, {
    required double globalRatePerKm,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/delivery-zones/$id',
      data: zone.toUpdateBody(globalRatePerKm: globalRatePerKm),
    );
    return DeliveryZone.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<void> deleteDeliveryZone(String id) async {
    await _api.dio.delete<Map<String, dynamic>>('/api/delivery-zones/$id');
  }

  Future<List<AdminVendor>> fetchVendors() async {
    final res = await _api.dio.get<List<dynamic>>('/api/admin/vendors');
    final data = res.data ?? [];
    return data
        .whereType<Map>()
        .map((e) => AdminVendor.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CreateVendorResult> createVendor({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String shopCategory,
    String? address,
    bool activate = true,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/admin/vendors',
      data: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'shop_category': shopCategory,
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        'activate': activate,
      },
    );
    return CreateVendorResult.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  Future<void> deleteVendor(String userId) async {
    await _api.dio.delete<Map<String, dynamic>>('/api/admin/vendors/$userId');
  }

  Future<List<AdminPendingProduct>> fetchPendingProducts() async {
    final res = await _api.dio.get<List<dynamic>>('/api/admin/pending-products');
    final data = res.data ?? [];
    return data
        .whereType<Map>()
        .map((e) => AdminPendingProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> approveProduct(String productId) async {
    await _api.dio.patch<Map<String, dynamic>>('/api/admin/products/$productId/approve');
  }

  Future<void> rejectProduct(String productId) async {
    await _api.dio.patch<Map<String, dynamic>>('/api/admin/products/$productId/reject');
  }

  Future<AdminVendor> setUserStatus({
    required String userId,
    required String status,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/admin/users/$userId/status',
      data: {'status': status},
    );
    return AdminVendor.fromJson(Map<String, dynamic>.from(res.data ?? {}));
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Admin request failed');
    }
    return err.toString();
  }
}
