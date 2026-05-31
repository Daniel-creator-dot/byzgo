import 'package:dio/dio.dart';

import '../models/location_point.dart';
import '../shared/delivery_pricing.dart';
import 'api_client.dart';

/// A single turn-by-turn maneuver along the route.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceText,
    required this.distanceMeters,
    required this.start,
    required this.end,
  });

  final String instruction;
  final String maneuver;
  final String distanceText;
  final int distanceMeters;
  final LocationPoint start;
  final LocationPoint end;
}

class RouteSummary {
  const RouteSummary({
    required this.etaMinutes,
    required this.durationSeconds,
    required this.durationText,
    required this.distanceText,
    required this.points,
    this.steps = const [],
  });

  final int etaMinutes;
  final int durationSeconds;
  final String durationText;
  final String distanceText;
  final List<LocationPoint> points;
  final List<RouteStep> steps;

  String get arrivalPhrase {
    final t = durationText.trim();
    if (t.isNotEmpty) {
      final lower = t.toLowerCase();
      if (lower.startsWith('arriving')) return t;
      return 'Arriving in $t';
    }
    if (etaMinutes <= 1) return 'Arriving in about 1 min';
    return 'Arriving in about $etaMinutes min';
  }

  DateTime expiresAtFrom(DateTime base) =>
      base.add(Duration(seconds: durationSeconds < 1 ? 60 : durationSeconds));
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
      final durationSec = (data['duration_seconds'] as num?)?.toInt() ?? 0;
      final etaMinutes = (data['eta_minutes'] as num?)?.toInt() ??
          (durationSec > 0 ? (durationSec / 60).ceil() : 1);
      final secs = durationSec > 0 ? durationSec : etaMinutes * 60;
      final steps = <RouteStep>[];
      final stepsRaw = data['steps'];
      if (stepsRaw is List) {
        for (final s in stepsRaw) {
          if (s is! Map) continue;
          final sLat = s['start_lat'];
          final sLng = s['start_lng'];
          final eLat = s['end_lat'];
          final eLng = s['end_lng'];
          if (sLat is! num || sLng is! num || eLat is! num || eLng is! num) {
            continue;
          }
          steps.add(RouteStep(
            instruction: s['instruction']?.toString() ?? '',
            maneuver: s['maneuver']?.toString() ?? '',
            distanceText: s['distance_text']?.toString() ?? '',
            distanceMeters: (s['distance_meters'] as num?)?.toInt() ?? 0,
            start: LocationPoint(
              address: '',
              lat: sLat.toDouble(),
              lng: sLng.toDouble(),
            ),
            end: LocationPoint(
              address: '',
              lat: eLat.toDouble(),
              lng: eLng.toDouble(),
            ),
          ));
        }
      }
      return RouteSummary(
        etaMinutes: etaMinutes < 1 ? 1 : etaMinutes,
        durationSeconds: secs < 1 ? 60 : secs,
        durationText: data['duration_text']?.toString() ?? '',
        distanceText: data['distance_text']?.toString() ?? '',
        points: points,
        steps: steps,
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
    // Urban motorcycle fallback when Directions API unavailable (~22 km/h).
    final minutes = (km / 0.37).ceil().clamp(1, 120);
    final secs = minutes * 60;
    return RouteSummary(
      etaMinutes: minutes,
      durationSeconds: secs,
      durationText: '$minutes min',
      distanceText: '${km.toStringAsFixed(1)} km (direct)',
      points: [origin, destination],
    );
  }
}
