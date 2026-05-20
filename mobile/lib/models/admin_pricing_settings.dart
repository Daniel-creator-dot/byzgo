class AdminPricingSettings {
  const AdminPricingSettings({
    required this.deliveryPricePerKm,
    required this.surgeEnabled,
    required this.surgeMultiplier,
    required this.surgeStartTime,
    required this.surgeEndTime,
    this.surgeActiveNow = false,
    this.ghanaTime,
  });

  final String deliveryPricePerKm;
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
      surgeEnabled: enabled,
      surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble() ??
          double.tryParse(json['surge_multiplier']?.toString() ?? '') ??
          1.5,
      surgeStartTime: json['surge_start_time']?.toString() ?? '17:00',
      surgeEndTime: json['surge_end_time']?.toString() ?? '21:00',
      surgeActiveNow: json['surge_active_now'] == true,
      ghanaTime: json['ghana_time']?.toString(),
    );
  }

  Map<String, dynamic> toPatchBody() => {
        'delivery_price_per_km': deliveryPricePerKm,
        'surge_enabled': surgeEnabled,
        'surge_multiplier': surgeMultiplier,
        'surge_start_time': surgeStartTime,
        'surge_end_time': surgeEndTime,
      };
}
