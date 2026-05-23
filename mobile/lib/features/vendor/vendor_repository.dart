import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/json_parse.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/vendor_shop_promo.dart';

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

  Future<VendorShopPromo> fetchShopPromo() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/vendor/shop-promo');
    final data = res.data;
    if (data == null) throw Exception('Empty shop promo response');
    return VendorShopPromo.fromJson(Map<String, dynamic>.from(data));
  }

  Future<String> uploadShopStoryFlyer(String filePath) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath, filename: 'story.jpg'),
      'folder': 'stories',
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/upload',
      data: formData,
    );
    final url = res.data?['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Upload failed — no flyer URL returned');
    }
    return url;
  }

  Future<VendorShopPromo> updateShopPromo({
    String? shopOpenStatus,
    String? shopStatusMessage,
    String? shopDiscountLabel,
    double? shopDiscountPercent,
    String? shopStoryImage,
    bool clearStatusMessage = false,
    bool clearDiscountLabel = false,
    bool clearDiscountPercent = false,
    bool clearShopStory = false,
  }) async {
    final data = <String, dynamic>{};
    if (shopOpenStatus != null) data['shop_open_status'] = shopOpenStatus;
    if (clearStatusMessage) {
      data['shop_status_message'] = null;
    } else if (shopStatusMessage != null) {
      data['shop_status_message'] = shopStatusMessage.trim();
    }
    if (clearDiscountLabel) {
      data['shop_discount_label'] = null;
    } else if (shopDiscountLabel != null) {
      data['shop_discount_label'] = shopDiscountLabel.trim();
    }
    if (clearDiscountPercent) {
      data['shop_discount_percent'] = null;
    } else if (shopDiscountPercent != null) {
      data['shop_discount_percent'] = shopDiscountPercent;
    }
    if (clearShopStory) {
      data['clear_shop_story'] = true;
    } else if (shopStoryImage != null) {
      data['shop_story_image'] = shopStoryImage;
    }
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/vendor/shop-promo',
      data: data,
    );
    final body = res.data;
    if (body == null) throw Exception('Empty shop promo response');
    return VendorShopPromo.fromJson(Map<String, dynamic>.from(body));
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
      'folder': 'products',
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
