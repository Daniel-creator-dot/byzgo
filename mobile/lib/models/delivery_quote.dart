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
  });

  final double distanceKm;
  final double deliveryFee;
  final double pricePerKm;
  final String? zone;
  final double? baseDeliveryFee;
  final bool surgeActive;
  final double? surgeMultiplier;

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) {
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
