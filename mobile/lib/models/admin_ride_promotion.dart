import '../core/json_parse.dart';

class AdminRidePromotion {
  const AdminRidePromotion({
    required this.id,
    required this.name,
    this.code,
    required this.serviceTypes,
    required this.customerDiscountPercent,
    required this.customerDiscountFixed,
    required this.riderBonusAmount,
    this.targetRegion,
    required this.enabled,
    this.startsAt,
    this.endsAt,
    required this.redemptionCount,
    this.maxRedemptions,
  });

  final String id;
  final String name;
  final String? code;
  final String serviceTypes;
  final double customerDiscountPercent;
  final double customerDiscountFixed;
  final double riderBonusAmount;
  final String? targetRegion;
  final bool enabled;
  final String? startsAt;
  final String? endsAt;
  final int redemptionCount;
  final int? maxRedemptions;

  factory AdminRidePromotion.fromJson(Map<String, dynamic> json) {
    return AdminRidePromotion(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
      serviceTypes: json['service_types']?.toString() ?? 'okada,keke,package',
      customerDiscountPercent:
          parseJsonDouble(json['customer_discount_percent']) ?? 0,
      customerDiscountFixed:
          parseJsonDouble(json['customer_discount_fixed']) ?? 0,
      riderBonusAmount: parseJsonDouble(json['rider_bonus_amount']) ?? 0,
      targetRegion: json['target_region']?.toString(),
      enabled: json['enabled'] == true,
      startsAt: json['starts_at']?.toString(),
      endsAt: json['ends_at']?.toString(),
      redemptionCount: parseJsonInt(json['redemption_count']) ?? 0,
      maxRedemptions: parseJsonInt(json['max_redemptions']),
    );
  }

  Map<String, dynamic> toBody() => {
        'name': name,
        if (code != null && code!.isNotEmpty) 'code': code,
        'service_types': serviceTypes,
        'customer_discount_percent': customerDiscountPercent,
        'customer_discount_fixed': customerDiscountFixed,
        'rider_bonus_amount': riderBonusAmount,
        if (targetRegion != null && targetRegion!.isNotEmpty)
          'target_region': targetRegion,
        'enabled': enabled,
        if (startsAt != null && startsAt!.isNotEmpty) 'starts_at': startsAt,
        if (endsAt != null && endsAt!.isNotEmpty) 'ends_at': endsAt,
        if (maxRedemptions != null) 'max_redemptions': maxRedemptions,
      };
}
