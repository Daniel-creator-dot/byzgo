import '../core/json_parse.dart';

class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.region,
    required this.minPrice,
    this.maxPrice,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String region;
  final double minPrice;
  final double? maxPrice;
  final bool isActive;

  factory DeliveryZone.fromJson(Map<String, dynamic> json) {
    return DeliveryZone(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      region: json['region']?.toString() ?? '',
      minPrice: parseJsonDouble(json['min_price']) ?? 0,
      maxPrice: parseJsonDouble(json['max_price']),
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toCreateBody({required double globalRatePerKm}) => {
        'name': name,
        'region': region,
        'base_price': minPrice > 0 ? minPrice : 5,
        'price_per_km': globalRatePerKm,
        'min_price': minPrice,
        'max_price': maxPrice,
      };

  Map<String, dynamic> toUpdateBody({required double globalRatePerKm}) => {
        'name': name,
        'region': region,
        'price_per_km': globalRatePerKm,
        'min_price': minPrice,
        'max_price': maxPrice,
        'is_active': isActive,
      };
}
