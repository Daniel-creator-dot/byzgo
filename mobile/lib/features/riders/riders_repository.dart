import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/location_point.dart';
import '../../models/nearby_rider.dart';
import '../../shared/rider_trip.dart';

/// Nearby online riders and live rider GPS for customer tracking.
class RidersRepository {
  RidersRepository(this._api);

  final ApiClient _api;

  Future<List<NearbyRider>> fetchNearby({
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
      final out = <NearbyRider>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final rider = NearbyRider.fromJson(Map<String, dynamic>.from(raw));
        if (rider.id.isNotEmpty && rider.hasCoords) out.add(rider);
      }
      return out;
    } on DioException catch (e) {
      throw RidersRepositoryException(ApiClient.messageFromDio(e));
    }
  }

  Future<LocationPoint?> fetchRiderLocation(String riderId) async {
    if (riderId.trim().isEmpty) return null;
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/riders/$riderId/location',
      );
      final data = res.data;
      if (data == null) return null;
      final lat = double.tryParse('${data['lat']}');
      final lng = double.tryParse('${data['lng']}');
      if (lat == null || lng == null || !hasValidCoords(lat, lng)) return null;
      return LocationPoint(address: 'Your biker', lat: lat, lng: lng);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
        return null;
      }
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
