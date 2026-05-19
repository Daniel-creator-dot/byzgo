import 'package:dio/dio.dart';

import '../models/location_point.dart';
import '../shared/ghana_location.dart';
import 'api_client.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

/// Ghana address search + reverse geocode via backend (works on Flutter web).
class PlacesService {
  PlacesService(this._api);

  final ApiClient _api;

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final q = input.trim();
    if (q.length < 2) return const [];

    try {
      final res = await _api.dio.get<dynamic>(
        '/api/maps/autocomplete',
        queryParameters: {'input': q},
      );
      final data = res.data;
      if (data is! Map) return const [];
      final list = data['predictions'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map(
            (e) => PlaceSuggestion(
              placeId: e['placeId']?.toString() ?? '',
              description: e['description']?.toString() ?? '',
            ),
          )
          .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
          .toList();
    } on DioException {
      return const [];
    }
  }

  Future<LocationPoint?> placeDetails(String placeId) async {
    if (placeId.trim().isEmpty) return null;
    try {
      final res = await _api.dio.get<dynamic>(
        '/api/maps/place-details',
        queryParameters: {'place_id': placeId},
      );
      final data = res.data;
      if (data is! Map) return null;
      final lat = data['lat'];
      final lng = data['lng'];
      if (lat is! num || lng is! num) return null;
      final address = data['address']?.toString().trim() ?? '';
      return LocationPoint(
        address: address.isEmpty ? formatCoordAddress(lat.toDouble(), lng.toDouble()) : address,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
      );
    } on DioException {
      return null;
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _api.dio.get<dynamic>(
        '/api/maps/reverse-geocode',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      final data = res.data;
      if (data is! Map) return null;
      final address = data['address']?.toString().trim();
      if (address == null || address.isEmpty) return null;
      return address;
    } on DioException {
      return null;
    }
  }

  Future<String> resolveAddressLabel(
    double lat,
    double lng, {
    String? existing,
  }) async {
    if (existing != null &&
        existing.trim().isNotEmpty &&
        !looksLikeCoordinates(existing) &&
        existing.trim().toLowerCase() != 'finding address…') {
      return existing.trim();
    }
    final label = await reverseGeocode(lat, lng);
    if (label != null && !looksLikeCoordinates(label)) return label;
    return displayLocationLabel(existing, lat, lng);
  }
}
