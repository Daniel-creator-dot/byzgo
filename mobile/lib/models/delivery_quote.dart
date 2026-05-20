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
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0,
      pricePerKm: (json['price_per_km'] as num?)?.toDouble() ?? 4,
      zone: json['zone']?.toString(),
      baseDeliveryFee: (json['base_delivery_fee'] as num?)?.toDouble(),
      surgeActive: json['surge_active'] == true,
      surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble(),
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
