import '../core/json_parse.dart';

class DeliveryQuote {
  const DeliveryQuote({
    required this.distanceKm,
    required this.deliveryFee,
    required this.pricePerKm,
    this.zone,
    this.baseDeliveryFee,
    this.surgeActive = false,
    this.surgeMultiplier,
    this.promotionDiscount = 0,
    this.promotionName,
    this.riderBonusAmount = 0,
    this.minFee,
    this.minApplied = false,
  });

  final double distanceKm;
  final double deliveryFee;
  final double pricePerKm;
  final String? zone;
  final double? baseDeliveryFee;
  final bool surgeActive;
  final double? surgeMultiplier;
  final double promotionDiscount;
  final String? promotionName;
  final double riderBonusAmount;
  final double? minFee;
  final bool minApplied;

  double get feeBeforePromotion => deliveryFee + promotionDiscount;

  DeliveryQuote copyWith({
    double? deliveryFee,
    double? minFee,
    bool? minApplied,
  }) {
    return DeliveryQuote(
      distanceKm: distanceKm,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      pricePerKm: pricePerKm,
      zone: zone,
      baseDeliveryFee: baseDeliveryFee,
      surgeActive: surgeActive,
      surgeMultiplier: surgeMultiplier,
      promotionDiscount: promotionDiscount,
      promotionName: promotionName,
      riderBonusAmount: riderBonusAmount,
      minFee: minFee ?? this.minFee,
      minApplied: minApplied ?? this.minApplied,
    );
  }

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) {
    final promo = json['promotion'];
    String? promoName;
    if (promo is Map) {
      promoName = promo['name']?.toString();
    }
    return DeliveryQuote(
      distanceKm: parseJsonDoubleOrZero(json['distance_km']),
      deliveryFee: parseJsonDouble(json['delivery_fee']) ??
          parseJsonDouble(json['price']) ??
          0,
      pricePerKm: parseJsonDouble(json['price_per_km']) ?? 4,
      zone: json['zone']?.toString(),
      baseDeliveryFee: parseJsonDouble(json['base_delivery_fee']),
      surgeActive: json['surge_active'] == true,
      surgeMultiplier: parseJsonDouble(json['surge_multiplier']),
      promotionDiscount: parseJsonDouble(json['promotion_discount']) ?? 0,
      promotionName: promoName,
      riderBonusAmount: parseJsonDouble(json['rider_bonus_amount']) ?? 0,
      minFee: parseJsonDouble(json['min_fee'] ?? json['zone_min_price']),
      minApplied: json['min_applied'] == true,
    );
  }
}

class ShopCartLine {
  const ShopCartLine({required this.productId, required this.name, required this.price, required this.quantity});

  final String productId;
  final String name;
  final double price;
  final int quantity;

  double get lineTotal => price * quantity;
}
