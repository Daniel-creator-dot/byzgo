import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/location_point.dart';
import '../../shared/rider_trip.dart';

/// Nearby online riders for customer map display.
class RidersRepository {
  RidersRepository(this._api);

  final ApiClient _api;

  Future<List<LocationPoint>> fetchNearby({
    required double lat,
    required double lng,
    int limit = 8,
  }) async {
    if (!hasValidCoords(lat, lng)) return [];
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/riders/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'limit': limit,
        },
      );
      final list = res.data?['riders'];
      if (list is! List) return [];
      final out = <LocationPoint>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final rLat = double.tryParse('${raw['lat']}');
        final rLng = double.tryParse('${raw['lng']}');
        if (rLat == null || rLng == null || !hasValidCoords(rLat, rLng)) continue;
        out.add(LocationPoint(address: 'Biker', lat: rLat, lng: rLng));
      }
      return out;
    } on DioException catch (e) {
      throw RidersRepositoryException(ApiClient.messageFromDio(e));
    }
  }
}

class RidersRepositoryException implements Exception {
  RidersRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
