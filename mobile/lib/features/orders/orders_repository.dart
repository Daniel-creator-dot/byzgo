import 'package:dio/dio.dart';



import '../../core/api_client.dart';

import '../../models/location_point.dart';

import '../../models/order.dart';

import '../../models/vendor.dart';



class OrdersRepository {

  OrdersRepository(this._api);



  final ApiClient _api;



  Future<List<Order>> fetchOrders() async {

    final res = await _api.dio.get<dynamic>('/api/orders');

    final data = res.data;

    if (data is! List) return [];

    return data

        .whereType<Map>()

        .map((e) => Order.fromJson(Map<String, dynamic>.from(e)))

        .toList();

  }



  Future<List<Vendor>> fetchVendors({String? region}) async {

    final res = await _api.dio.get<dynamic>(

      '/api/vendors',

      queryParameters: region != null ? {'region': region} : null,

    );

    final data = res.data;

    if (data is! List) return [];

    return data

        .whereType<Map>()

        .map((e) => Vendor.fromJson(Map<String, dynamic>.from(e)))

        .toList();

  }



  Future<Order> createCourierOrder({

    required LocationPoint pickup,

    required LocationPoint destination,

    required double deliveryFee,

    String itemDescription = 'Package',

    String paymentMethod = 'pay_on_delivery',

  }) async {

    final res = await _api.dio.post<Map<String, dynamic>>(

      '/api/orders',

      data: {

        'items': [

          {

            'id': 'courier-1',

            'name': 'Delivery: $itemDescription',

            'quantity': 1,

            'price': deliveryFee,

          },

        ],

        'total': deliveryFee,

        'order_type': 'courier',

        'address': destination.address,

        'pickup': pickup.address,

        'lat': destination.lat,

        'lng': destination.lng,

        'pickup_lat': pickup.lat,

        'pickup_lng': pickup.lng,

        'delivery_fee': deliveryFee,

        'payment_method': paymentMethod,

      },

    );

    final data = res.data;

    if (data == null) throw Exception('Empty order response');

    return Order.fromJson(Map<String, dynamic>.from(data));

  }



  Future<Order> acceptOrder({

    required String orderId,

    required String riderId,

    required String currentStatus,

  }) async {

    final res = await _api.dio.patch<Map<String, dynamic>>(

      '/api/orders/$orderId',

      data: {

        'status': currentStatus,

        'riderId': riderId,

      },

    );

    final data = res.data;

    if (data == null) throw Exception('Empty accept response');

    return Order.fromJson(Map<String, dynamic>.from(data));

  }



  Future<Order> updateOrderStatus({

    required String orderId,

    required String status,

    String? riderId,

  }) async {

    final res = await _api.dio.patch<Map<String, dynamic>>(

      '/api/orders/$orderId',

      data: {

        'status': status,

        if (riderId != null) 'riderId': riderId,

      },

    );

    final data = res.data;

    if (data == null) throw Exception('Empty order response');

    return Order.fromJson(Map<String, dynamic>.from(data));

  }



  Future<Order> markArrived(String orderId) async {

    final res = await _api.dio.patch<Map<String, dynamic>>(

      '/api/orders/$orderId/arrive',

    );

    final data = res.data;

    if (data == null) throw Exception('Empty arrive response');

    return Order.fromJson(Map<String, dynamic>.from(data));

  }



  Future<Order> completeDelivery({

    required String orderId,

    required String code,

  }) async {

    final res = await _api.dio.post<Map<String, dynamic>>(

      '/api/orders/$orderId/complete-delivery',

      data: {'code': code},

    );

    final data = res.data;

    if (data == null) throw Exception('Empty complete response');

    return Order.fromJson(Map<String, dynamic>.from(data));

  }



  Future<void> declineOrder(String orderId) async {

    await _api.dio.post('/api/orders/$orderId/decline');

  }



  static String errorMessage(Object err) {

    if (err is DioException) {

      final status = err.response?.statusCode;

      if (status == 409) {

        return 'This ride was already taken by another rider.';

      }

      return ApiClient.messageFromDio(err, 'Order request failed');

    }

    return err.toString();

  }

}


