import '../core/json_parse.dart';



/// Subset of `Order` from `src/types.ts` — extend as screens are ported.

class Order {

  const Order({

    required this.id,

    required this.customerId,

    required this.customerName,

    required this.total,

    required this.status,

    required this.createdAt,

    required this.address,

    required this.vendorId,

    this.items = const [],

    this.riderId,

    this.pickup,

    this.pickupAddress,

    this.orderType,

    this.lat,

    this.lng,

    this.pickupLat,

    this.pickupLng,

    this.deliveryFee,

    this.expiresAt,

    this.dispatchWave,

    this.paymentStatus,

    this.paymentMethod,

    this.customerPaymentAck,

    this.rating,

  });



  final String id;

  final String customerId;

  final String customerName;

  final List<OrderItem> items;

  final double total;

  final String status;

  final String createdAt;

  final String address;

  final String? pickup;

  final String? pickupAddress;

  final String? orderType;

  final String vendorId;

  final String? riderId;

  final double? lat;

  final double? lng;

  final double? pickupLat;

  final double? pickupLng;

  final double? deliveryFee;

  final String? expiresAt;

  final int? dispatchWave;

  final String? paymentStatus;

  final String? paymentMethod;

  final String? customerPaymentAck;

  final int? rating;



  bool get isCourier => orderType == 'courier';



  factory Order.fromJson(Map<String, dynamic> json) {

    final rawItems = json['items'];

    List<OrderItem> items = [];

    if (rawItems is List) {

      items = rawItems

          .whereType<Map>()

          .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e)))

          .toList();

    }

    return Order(

      id: json['id']?.toString() ?? '',

      customerId: (json['customer_id'] ?? json['customerId'])?.toString() ?? '',

      customerName: json['customerName']?.toString() ??

          json['customer_name']?.toString() ??

          '',

      items: items,

      total: parseJsonDoubleOrZero(json['total']),

      status: json['status']?.toString() ?? 'pending',

      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',

      address: json['address']?.toString() ?? '',

      pickup: (json['pickup'] ?? json['pickup_address'])?.toString(),

      pickupAddress: json['pickup_address']?.toString(),

      orderType: (json['orderType'] ?? json['order_type'])?.toString(),

      vendorId: (json['vendor_id'] ?? json['vendorId'])?.toString() ?? '',

      riderId: (json['rider_id'] ?? json['riderId'])?.toString(),

      lat: parseJsonDouble(json['lat']),

      lng: parseJsonDouble(json['lng']),

      pickupLat: parseJsonDouble(json['pickup_lat']),

      pickupLng: parseJsonDouble(json['pickup_lng']),

      deliveryFee: parseJsonDouble(json['delivery_fee']),

      expiresAt: (json['expiresAt'] ?? json['expires_at'])?.toString(),

      dispatchWave: parseJsonInt(json['dispatchWave'] ?? json['dispatch_wave']),

      paymentStatus: json['payment_status']?.toString(),

      paymentMethod: json['payment_method']?.toString(),

      customerPaymentAck: json['customer_payment_ack']?.toString(),

      rating: parseJsonInt(json['rating']),

    );

  }

}



class OrderItem {

  const OrderItem({

    required this.id,

    required this.name,

    required this.quantity,

    required this.price,

  });



  final String id;

  final String name;

  final int quantity;

  final double price;



  factory OrderItem.fromJson(Map<String, dynamic> json) {

    return OrderItem(

      id: json['id']?.toString() ?? '',

      name: json['name']?.toString() ?? '',

      quantity: parseJsonInt(json['quantity']) ?? 1,

      price: parseJsonDoubleOrZero(json['price']),

    );

  }

}


