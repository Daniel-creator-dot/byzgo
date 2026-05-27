import '../core/json_parse.dart';

class AdminPricingSettings {
  const AdminPricingSettings({
    required this.deliveryPricePerKm,
    required this.deliveryMinFee,
    required this.deliveryMaxFee,
    required this.surgeEnabled,
    required this.surgeMultiplier,
    required this.surgeStartTime,
    required this.surgeEndTime,
    this.commissionPercent = '10',
    this.commissionInsurancePercent = '3',
    this.commissionPlatformPercent = '7',
    this.surgeActiveNow = false,
    this.ghanaTime,
  });

  final String deliveryPricePerKm;
  final String deliveryMinFee;
  final String deliveryMaxFee;
  final String commissionPercent;
  final String commissionInsurancePercent;
  final String commissionPlatformPercent;
  final bool surgeEnabled;
  final double surgeMultiplier;
  final String surgeStartTime;
  final String surgeEndTime;
  final bool surgeActiveNow;
  final String? ghanaTime;

  factory AdminPricingSettings.fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['surge_enabled'];
    final enabled = enabledRaw == true ||
        enabledRaw == 'true' ||
        enabledRaw == 1 ||
        enabledRaw == '1';
    return AdminPricingSettings(
      deliveryPricePerKm:
          json['delivery_price_per_km']?.toString() ?? '4',
      deliveryMinFee: json['delivery_min_fee']?.toString() ?? '',
      deliveryMaxFee: json['delivery_max_fee']?.toString() ?? '',
      commissionPercent: json['commission_percent']?.toString() ?? '10',
      commissionInsurancePercent:
          json['commission_insurance_percent']?.toString() ?? '3',
      commissionPlatformPercent:
          json['commission_platform_percent']?.toString() ?? '7',
      surgeEnabled: enabled,
      surgeMultiplier: parseJsonDouble(json['surge_multiplier']) ?? 1.5,
      surgeStartTime: json['surge_start_time']?.toString() ?? '17:00',
      surgeEndTime: json['surge_end_time']?.toString() ?? '21:00',
      surgeActiveNow: json['surge_active_now'] == true,
      ghanaTime: json['ghana_time']?.toString(),
    );
  }

  Map<String, dynamic> toPatchBody() => {
        'delivery_price_per_km': deliveryPricePerKm,
        'delivery_min_fee': deliveryMinFee.trim(),
        'delivery_max_fee': deliveryMaxFee.trim(),
        'commission_percent': commissionPercent,
        'commission_insurance_percent': commissionInsurancePercent,
        'commission_platform_percent': commissionPlatformPercent,
        'surge_enabled': surgeEnabled,
        'surge_multiplier': surgeMultiplier,
        'surge_start_time': surgeStartTime,
        'surge_end_time': surgeEndTime,
      };
}
