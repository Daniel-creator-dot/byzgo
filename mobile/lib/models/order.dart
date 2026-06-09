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

    this.offerDistanceKm,

    this.paymentStatus,

    this.paymentMethod,

    this.customerPaymentAck,

    this.deliveryCode,

    this.rating,
    this.customerPhone,
    this.customerAvatarUrl,
    this.customerAvgRating,
    this.riderPhone,
    this.riderName,
    this.riderAvatarUrl,
    this.riderAvgRating,
    this.riderRatingCount,
    this.riderTier,
    this.vendorName,
    this.pulseGuideLat,
    this.pulseGuideLng,
    this.pulseGuideAt,
    this.pulseGuidePhase,
    this.pulseGuideActive,

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

  /// Distance from this rider to pickup (km), set on `ride:incoming`.
  final double? offerDistanceKm;

  final String? paymentStatus;

  final String? paymentMethod;

  final String? customerPaymentAck;

  final String? deliveryCode;

  final int? rating;

  final String? customerPhone;

  final String? customerAvatarUrl;

  final double? customerAvgRating;

  final String? riderPhone;

  final String? riderName;

  final String? riderAvatarUrl;

  /// Driver's average rating across rated trips (1–5), if assigned.
  final double? riderAvgRating;

  /// How many of the driver's trips have been rated.
  final int? riderRatingCount;

  /// Driver gold tier from the backend: 'gold' | 'silver' | 'bronze' | 'new'.
  final String? riderTier;

  final String? vendorName;

  final double? pulseGuideLat;
  final double? pulseGuideLng;
  final String? pulseGuideAt;
  final String? pulseGuidePhase;
  final bool? pulseGuideActive;

  bool get isCourier => orderType == 'courier';

  bool get hasShopPickup => vendorId.trim().isNotEmpty;

  bool get isCancelled => status == 'cancelled';

  /// Strip rider assignment from cancelled trips so UI never shows a picked rider.
  Order withoutAssignedRider() {
    return Order(
      id: id,
      customerId: customerId,
      customerName: customerName,
      items: items,
      total: total,
      status: status,
      createdAt: createdAt,
      address: address,
      vendorId: vendorId,
      pickup: pickup,
      pickupAddress: pickupAddress,
      orderType: orderType,
      lat: lat,
      lng: lng,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryFee: deliveryFee,
      expiresAt: expiresAt,
      dispatchWave: dispatchWave,
      offerDistanceKm: offerDistanceKm,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      customerPaymentAck: customerPaymentAck,
      deliveryCode: deliveryCode,
      rating: rating,
      customerPhone: customerPhone,
      customerAvatarUrl: customerAvatarUrl,
      customerAvgRating: customerAvgRating,
      vendorName: vendorName,
      pulseGuideLat: pulseGuideLat,
      pulseGuideLng: pulseGuideLng,
      pulseGuideAt: pulseGuideAt,
      pulseGuidePhase: pulseGuidePhase,
      pulseGuideActive: pulseGuideActive,
    );
  }

  Order normalizedForCustomerTrip() {
    if (!isCancelled) return this;
    return withoutAssignedRider();
  }

  static int _tripStatusRank(String value) {
    switch (value) {
      case 'pending':
        return 0;
      case 'preparing':
        return 1;
      case 'ready':
        return 2;
      case 'picked_up':
        return 3;
      case 'arrived':
        return 4;
      case 'delivered':
        return 5;
      case 'cancelled':
        return -2;
      default:
        return 0;
    }
  }

  static bool _hasAssignedRiderId(String? id) =>
      id != null && id.trim().isNotEmpty;

  /// Keep rider assignment and forward trip status when a stale socket payload
  /// arrives without the assigned biker.
  Order mergeWithPrevious(Order prev) {
    if (prev.id != id) return normalizedForCustomerTrip();
    var next = normalizedForCustomerTrip();
    if (prev.status == 'cancelled' && next.status != 'cancelled') return prev;

    final prevHasRider = _hasAssignedRiderId(prev.riderId);
    final nextHasRider = _hasAssignedRiderId(next.riderId);
    var riderId = next.riderId;
    var riderName = next.riderName;
    var riderPhone = next.riderPhone;
    var riderAvatarUrl = next.riderAvatarUrl;
    var riderAvgRating = next.riderAvgRating;
    var riderRatingCount = next.riderRatingCount;
    var riderTier = next.riderTier;
    var status = next.status;

    if (prevHasRider &&
        !nextHasRider &&
        !next.isCancelled &&
        next.status != 'delivered') {
      riderId = prev.riderId;
      riderName = next.riderName ?? prev.riderName;
      riderPhone = next.riderPhone ?? prev.riderPhone;
      riderAvatarUrl = next.riderAvatarUrl ?? prev.riderAvatarUrl;
      riderAvgRating = next.riderAvgRating ?? prev.riderAvgRating;
      riderRatingCount = next.riderRatingCount ?? prev.riderRatingCount;
      riderTier = next.riderTier ?? prev.riderTier;
    }

    if (_tripStatusRank(prev.status) > _tripStatusRank(status) &&
        !next.isCancelled) {
      status = prev.status;
      if (prevHasRider && !nextHasRider) {
        riderId = prev.riderId;
        riderName = prev.riderName ?? riderName;
        riderPhone = prev.riderPhone ?? riderPhone;
        riderAvatarUrl = prev.riderAvatarUrl ?? riderAvatarUrl;
        riderAvgRating = prev.riderAvgRating ?? riderAvgRating;
        riderRatingCount = prev.riderRatingCount ?? riderRatingCount;
        riderTier = prev.riderTier ?? riderTier;
      }
    }

    if (riderId == next.riderId &&
        riderName == next.riderName &&
        riderPhone == next.riderPhone &&
        riderAvatarUrl == next.riderAvatarUrl &&
        riderAvgRating == next.riderAvgRating &&
        riderRatingCount == next.riderRatingCount &&
        riderTier == next.riderTier &&
        status == next.status) {
      return next;
    }

    return Order(
      id: next.id,
      customerId: next.customerId,
      customerName: next.customerName,
      items: next.items,
      total: next.total,
      status: status,
      createdAt: next.createdAt,
      address: next.address,
      vendorId: next.vendorId,
      pickup: next.pickup,
      pickupAddress: next.pickupAddress,
      orderType: next.orderType,
      lat: next.lat,
      lng: next.lng,
      pickupLat: next.pickupLat,
      pickupLng: next.pickupLng,
      deliveryFee: next.deliveryFee,
      expiresAt: next.expiresAt,
      dispatchWave: next.dispatchWave,
      offerDistanceKm: next.offerDistanceKm,
      paymentStatus: next.paymentStatus,
      paymentMethod: next.paymentMethod,
      customerPaymentAck: next.customerPaymentAck,
      deliveryCode: next.deliveryCode,
      rating: next.rating,
      customerPhone: next.customerPhone,
      customerAvatarUrl: next.customerAvatarUrl,
      customerAvgRating: next.customerAvgRating,
      riderId: riderId,
      riderPhone: riderPhone,
      riderName: riderName,
      riderAvatarUrl: riderAvatarUrl,
      riderAvgRating: riderAvgRating,
      riderRatingCount: riderRatingCount,
      riderTier: riderTier,
      vendorName: next.vendorName,
      pulseGuideLat: next.pulseGuideLat,
      pulseGuideLng: next.pulseGuideLng,
      pulseGuideAt: next.pulseGuideAt,
      pulseGuidePhase: next.pulseGuidePhase,
      pulseGuideActive: next.pulseGuideActive,
    );
  }



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

      offerDistanceKm: parseJsonDouble(
        json['offerDistanceKm'] ?? json['offer_distance_km'] ?? json['pickupDistanceKm'] ?? json['pickup_distance_km'],
      ),

      paymentStatus: json['payment_status']?.toString(),

      paymentMethod: json['payment_method']?.toString(),

      customerPaymentAck: json['customer_payment_ack']?.toString(),

      deliveryCode: json['delivery_code']?.toString(),

      rating: parseJsonInt(json['rating']),

      customerPhone: (json['customerPhone'] ?? json['customer_phone'])?.toString(),

      customerAvatarUrl:
          (json['customerAvatarUrl'] ?? json['customer_avatar_url'])?.toString(),

      customerAvgRating: parseJsonDouble(
        json['customerAvgRating'] ?? json['customer_avg_rating'],
      ),

      riderPhone: (json['riderPhone'] ?? json['rider_phone'])?.toString(),

      riderName: (json['riderName'] ?? json['rider_name'])?.toString(),

      riderAvatarUrl:
          (json['riderAvatarUrl'] ?? json['rider_avatar_url'])?.toString(),

      riderAvgRating: parseJsonDouble(
        json['riderAvgRating'] ?? json['rider_avg_rating'],
      ),
      riderRatingCount: parseJsonInt(
        json['riderRatingCount'] ?? json['rider_rating_count'],
      ),
      riderTier: (json['riderTier'] ?? json['rider_tier'])?.toString(),

      vendorName: (json['vendorName'] ?? json['vendor_name'])?.toString(),

      pulseGuideLat: parseJsonDouble(json['pulseGuideLat'] ?? json['pulse_guide_lat']),
      pulseGuideLng: parseJsonDouble(json['pulseGuideLng'] ?? json['pulse_guide_lng']),
      pulseGuideAt: (json['pulseGuideAt'] ?? json['pulse_guide_at'])?.toString(),
      pulseGuidePhase: (json['pulseGuidePhase'] ?? json['pulse_guide_phase'])?.toString(),
      pulseGuideActive: json['pulseGuideActive'] == true || json['pulse_guide_active'] == true,

    );

  }

  Order copyWithPulseGuide({
    required double lat,
    required double lng,
    required String phase,
    String? at,
    bool active = true,
  }) {
    return Order(
      id: id,
      customerId: customerId,
      customerName: customerName,
      items: items,
      total: total,
      status: status,
      createdAt: createdAt,
      address: address,
      vendorId: vendorId,
      riderId: riderId,
      pickup: pickup,
      pickupAddress: pickupAddress,
      orderType: orderType,
      lat: lat,
      lng: lng,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryFee: deliveryFee,
      expiresAt: expiresAt,
      dispatchWave: dispatchWave,
      offerDistanceKm: offerDistanceKm,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      customerPaymentAck: customerPaymentAck,
      deliveryCode: deliveryCode,
      rating: rating,
      customerPhone: customerPhone,
      customerAvatarUrl: customerAvatarUrl,
      customerAvgRating: customerAvgRating,
      riderPhone: riderPhone,
      riderName: riderName,
      riderAvatarUrl: riderAvatarUrl,
      riderAvgRating: riderAvgRating,
      riderRatingCount: riderRatingCount,
      riderTier: riderTier,
      vendorName: vendorName,
      pulseGuideLat: lat,
      pulseGuideLng: lng,
      pulseGuideAt: at ?? DateTime.now().toUtc().toIso8601String(),
      pulseGuidePhase: phase,
      pulseGuideActive: active,
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


