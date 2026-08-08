import 'dart:math';

import 'vehicle_type.dart';
class OkadaFare {
  static const double earthRadiusKm = 6371.0;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double estimate({
    required String vehicleType,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    int passengers = 1,
  }) {
    final km = distanceKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    final isTricycle = vehicleType == VehicleType.tricycle;

    final base = isTricycle ? 8.0 : 5.0;
    final perKm = isTricycle ? 3.0 : 2.5;
    final minimum = isTricycle ? 12.0 : 8.0;
    final passengerSurcharge =
        max(0, passengers - 1) * (isTricycle ? 2.0 : 1.5);

    final raw = base + (km * perKm) + passengerSurcharge;
    return double.parse(max(minimum, raw).toStringAsFixed(2));
  }

  static int etaMinutes(double km) {
    return max(3, (km / 22 * 60).ceil());
  }

  static double _degToRad(double deg) => deg * pi / 180;
}
