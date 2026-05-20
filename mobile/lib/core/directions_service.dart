import 'package:dio/dio.dart';

import '../models/location_point.dart';
import '../shared/delivery_pricing.dart';
import 'api_client.dart';

class RouteSummary {
  const RouteSummary({
    required this.etaMinutes,
    required this.durationText,
    required this.distanceText,
    required this.points,
  });

  final int etaMinutes;
  final String durationText;
  final String distanceText;
  final List<LocationPoint> points;

  String get arrivalPhrase {
    if (etaMinutes <= 1) return 'Arriving in about 1 min';
    return 'Arriving in about $etaMinutes min';
  }
}

/// Driving ETA + route polyline via backend Google Directions proxy.
class DirectionsService {
  DirectionsService(this._api);

  final ApiClient _api;

  Future<RouteSummary?> fetchRoute({
    required LocationPoint origin,
    required LocationPoint destination,
  }) async {
    if (!origin.hasCoords || !destination.hasCoords) return null;
    try {
      final res = await _api.dio.get<dynamic>(
        '/api/maps/directions',
        queryParameters: {
          'origin_lat': origin.lat,
          'origin_lng': origin.lng,
          'dest_lat': destination.lat,
          'dest_lng': destination.lng,
        },
      );
      final data = res.data;
      if (data is! Map) return _fallback(origin, destination);
      final pointsRaw = data['points'];
      final points = <LocationPoint>[];
      if (pointsRaw is List) {
        for (final p in pointsRaw) {
          if (p is! Map) continue;
          final lat = p['lat'];
          final lng = p['lng'];
          if (lat is num && lng is num) {
            points.add(LocationPoint(
              address: '',
              lat: lat.toDouble(),
              lng: lng.toDouble(),
            ));
          }
        }
      }
      final etaMinutes = (data['eta_minutes'] as num?)?.toInt() ?? 1;
      return RouteSummary(
        etaMinutes: etaMinutes < 1 ? 1 : etaMinutes,
        durationText: data['duration_text']?.toString() ?? '',
        distanceText: data['distance_text']?.toString() ?? '',
        points: points,
      );
    } on DioException {
      return _fallback(origin, destination);
    }
  }

  RouteSummary? _fallback(LocationPoint origin, LocationPoint destination) {
    final km = haversineDistanceKm(
      origin.lat,
      origin.lng,
      destination.lat,
      destination.lng,
    );
    final minutes = (km / 0.45).ceil().clamp(1, 120);
    return RouteSummary(
      etaMinutes: minutes,
      durationText: '$minutes min',
      distanceText: '${km.toStringAsFixed(1)} km',
      points: [origin, destination],
    );
  }
}
