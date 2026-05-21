import 'dart:math' as math;

import '../models/order.dart';

/// Live "I'm here" GPS pulse — [Pulse Guide™] for wrong-address pickups in dense cities.
const pulseGuideTtl = Duration(minutes: 8);

bool orderAllowsPulseGuide(Order order) {
  if (order.riderId == null || order.riderId!.isEmpty) return false;
  return pulseGuidePhase(order).isNotEmpty;
}

/// `pickup` while rider is heading to customer/shop; `dropoff` while en route or at door.
String pulseGuidePhase(Order order) {
  if (['picked_up', 'arrived'].contains(order.status)) return 'dropoff';
  if (['pending', 'ready', 'preparing'].contains(order.status)) return 'pickup';
  return '';
}

bool isPulseGuideActive(Order order) {
  final lat = order.pulseGuideLat;
  final lng = order.pulseGuideLng;
  final at = order.pulseGuideAt;
  if (lat == null || lng == null || at == null || at.isEmpty) return false;
  try {
    final t = DateTime.parse(at).toUtc();
    return DateTime.now().toUtc().difference(t) < pulseGuideTtl;
  } catch (_) {
    return false;
  }
}

int? pulseGuideDistanceMeters(
  Order order, {
  required double? riderLat,
  required double? riderLng,
}) {
  if (!isPulseGuideActive(order)) return null;
  final lat = order.pulseGuideLat;
  final lng = order.pulseGuideLng;
  if (lat == null || lng == null || riderLat == null || riderLng == null) return null;
  return _haversineMeters(riderLat, riderLng, lat, lng).round();
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String formatPulseDistance(int? meters) {
  if (meters == null) return '';
  if (meters < 1000) return '${meters}m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}
