import 'dart:math' as math;

/// Port of `src/lib/deliveryPricing.ts`.

const double defaultDeliveryPricePerKm = 4;

double haversineDistanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  if (lat1 == 0 || lon1 == 0 || lat2 == 0 || lon2 == 0) return 0;
  const r = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

double deliveryFeeFromDistanceKm(
  double distanceKm,
  double pricePerKm, {
  double? min,
  double? max,
}) {
  final rate =
      pricePerKm > 0 ? pricePerKm : defaultDeliveryPricePerKm;
  var fee = distanceKm * rate;
  if (min != null) fee = fee < min ? min : fee;
  if (max != null) fee = fee > max ? max : fee;
  return (fee * 100).roundToDouble() / 100;
}

double _deg2rad(double deg) => deg * (math.pi / 180);
