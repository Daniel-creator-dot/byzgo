import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/order.dart';
import '../../models/product.dart';

class VendorDashboardStats {
  const VendorDashboardStats({
    required this.activeOrders,
    required this.inStock,
    required this.outOfStock,
    required this.pendingApproval,
    required this.revenue7d,
  });

  final int activeOrders;
  final int inStock;
  final int outOfStock;
  final int pendingApproval;
  final double revenue7d;

  factory VendorDashboardStats.fromJson(Map<String, dynamic> json) {
    return VendorDashboardStats(
      activeOrders: (json['active_orders'] as num?)?.toInt() ?? 0,
      inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
      outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
      pendingApproval: (json['pending_approval'] as num?)?.toInt() ?? 0,
      revenue7d: (json['revenue_7d'] as num?)?.toDouble() ?? 0,
    );
  }
}

class VendorDashboard {
  const VendorDashboard({
    required this.stats,
    required this.products,
    required this.recentOrders,
  });

  final VendorDashboardStats stats;
  final List<Product> products;
  final List<Order> recentOrders;
}

class VendorRepository {
  VendorRepository(this._api);

  final ApiClient _api;

  Future<VendorDashboard> fetchDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/vendor/dashboard');
    final data = res.data;
    if (data == null) throw Exception('Empty vendor dashboard');
    final products = (data['products'] as List?)
            ?.whereType<Map>()
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
    final orders = (data['recentOrders'] as List?)
            ?.whereType<Map>()
            .map((e) => Order.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
    return VendorDashboard(
      stats: VendorDashboardStats.fromJson(
        Map<String, dynamic>.from(data['stats'] as Map? ?? {}),
      ),
      products: products,
      recentOrders: orders,
    );
  }

  Future<Product> setProductAvailability({
    required String productId,
    required bool isAvailable,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/products/$productId',
      data: {'is_available': isAvailable},
    );
    final data = res.data;
    if (data == null) throw Exception('Empty product response');
    return Product.fromJson(Map<String, dynamic>.from(data));
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Vendor request failed');
    }
    return err.toString();
  }
}
