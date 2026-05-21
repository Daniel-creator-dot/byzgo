import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';
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
      activeOrders: parseJsonInt(json['active_orders']) ?? 0,
      inStock: parseJsonInt(json['in_stock']) ?? 0,
      outOfStock: parseJsonInt(json['out_of_stock']) ?? 0,
      pendingApproval: parseJsonInt(json['pending_approval']) ?? 0,
      revenue7d: parseJsonDouble(json['revenue_7d']) ?? 0,
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

  Future<List<Product>> fetchProducts({
    String search = '',
    int limit = 200,
    int offset = 0,
  }) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/vendor/products',
      queryParameters: {
        if (search.trim().isNotEmpty) 'q': search.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    final list = res.data ?? [];
    return list
        .whereType<Map>()
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

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

  Future<String> uploadImage(String filePath) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        filePath,
        filename: 'product.jpg',
      ),
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/upload',
      data: formData,
    );
    final url = res.data?['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Upload failed — no image URL returned');
    }
    return url;
  }

  Future<Product> createProduct({
    required String name,
    required String description,
    required double price,
    required String category,
    required String imageUrl,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/products',
      data: {
        'name': name,
        'description': description,
        'price': price,
        'category': category,
        'image_url': imageUrl,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('Empty product response');
    return Product.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Product> updateProduct({
    required String productId,
    required String name,
    required String description,
    required double price,
    required String category,
    String? imageUrl,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'description': description,
      'price': price,
      'category': category,
    };
    if (imageUrl != null && imageUrl.isNotEmpty) {
      data['image_url'] = imageUrl;
    }
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/products/$productId',
      data: data,
    );
    final body = res.data;
    if (body == null) throw Exception('Empty product response');
    return Product.fromJson(Map<String, dynamic>.from(body));
  }

  Future<void> deleteProduct(String productId) async {
    await _api.dio.delete('/api/products/$productId');
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Vendor request failed');
    }
    return err.toString();
  }
}
