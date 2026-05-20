import 'package:dio/dio.dart';



import '../../core/api_client.dart';

import '../../models/delivery_quote.dart';
import '../../models/location_point.dart';

import '../../models/order.dart';

import '../../models/product.dart';
import '../../models/trip_message.dart';
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

  Future<List<Product>> fetchProducts({required String vendorId}) async {
    final res = await _api.dio.get<dynamic>(
      '/api/products',
      queryParameters: {'vendor_id': vendorId},
    );
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
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

  Future<DeliveryQuote> calculateRouteDelivery({
    required double pickupLat,
    required double pickupLng,
    required double destLat,
    required double destLng,
    String? pickupRegion,
    String? destinationRegion,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/delivery/calculate',
      data: {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dest_lat': destLat,
        'dest_lng': destLng,
        if (pickupRegion != null) 'pickup_region': pickupRegion,
        if (destinationRegion != null) 'destination_region': destinationRegion,
      },
    );
    final data = res.data;
    if (data == null) throw Exception('Empty delivery quote');
    return DeliveryQuote.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Order> createShopCourierOrder({
    required String vendorId,
    required LocationPoint pickup,
    required LocationPoint destination,
    required List<ShopCartLine> lines,
    required double deliveryFee,
    String itemDescription = 'Shop order',
    String paymentMethod = 'pay_on_delivery',
  }) async {
    final itemsSubtotal =
        lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final total = ((itemsSubtotal + deliveryFee) * 100).round() / 100;

    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders',
      data: {
        'vendorId': vendorId,
        'items': [
          ...lines.map(
            (l) => {
              'id': l.productId,
              'name': l.name,
              'quantity': l.quantity,
              'price': l.price,
            },
          ),
        ],
        'total': total,
        'order_type': 'courier',
        'address': destination.address,
        'pickup': pickup.address,
        'lat': destination.lat,
        'lng': destination.lng,
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'delivery_fee': deliveryFee,
        'payment_method': paymentMethod,
        'itemDescription': itemDescription,
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

  Future<Order> cancelOrder(String orderId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders/$orderId/cancel',
    );
    final data = res.data;
    if (data == null) throw Exception('Empty cancel response');
    return Order.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Order> payAtDeliveryWallet(String orderId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders/$orderId/pay-at-delivery',
      data: {'payment_method': 'wallet'},
    );
    final data = res.data;
    if (data == null) throw Exception('Empty payment response');
    return Order.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Order> payAtDeliveryReference({
    required String orderId,
    required String paymentReference,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders/$orderId/pay-at-delivery',
      data: {'payment_reference': paymentReference.trim()},
    );
    final data = res.data;
    if (data == null) throw Exception('Empty payment response');
    return Order.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Order> ackCashPayment(String orderId) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders/$orderId/ack-cash',
    );
    final data = res.data;
    if (data == null) throw Exception('Empty ack response');
    return Order.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<TripMessage>> fetchTripMessages(String orderId) async {
    final res = await _api.dio.get<dynamic>('/api/orders/$orderId/messages');
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => TripMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TripMessage> sendTripMessage(String orderId, String body) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/orders/$orderId/messages',
      data: {'body': body},
    );
    final data = res.data;
    if (data == null) throw Exception('Empty message response');
    return TripMessage.fromJson(Map<String, dynamic>.from(data));
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


