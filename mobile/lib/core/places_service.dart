import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';

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

class PlacesSearchResult {
  const PlacesSearchResult({
    required this.suggestions,
    this.errorMessage,
  });

  final List<PlaceSuggestion> suggestions;
  final String? errorMessage;

  bool get ok => errorMessage == null;
}

/// Ghana address search + reverse geocode via backend (works on Flutter web).
class PlacesService {
  PlacesService(this._api);

  final ApiClient _api;

  static String messageFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    if (e.response?.statusCode == 503) {
      return 'Address search is temporarily unavailable. Try again in a moment.';
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'No connection — check your internet and try again.';
    }
    return 'Could not search addresses. Try again.';
  }

  Future<PlacesSearchResult> search(String input) async {
    final q = input.trim();
    if (q.length < 2) {
      return const PlacesSearchResult(suggestions: []);
    }

    try {
      final res = await _api.dio.get<dynamic>(
        '/api/maps/autocomplete',
        queryParameters: {'input': q},
      );
      final data = res.data;
      if (data is! Map) {
        return const PlacesSearchResult(
          suggestions: [],
          errorMessage: 'Address search returned an invalid response.',
        );
      }
      final list = data['predictions'];
      if (list is! List) {
        return const PlacesSearchResult(suggestions: []);
      }
      final suggestions = list
          .whereType<Map>()
          .map(
            (e) => PlaceSuggestion(
              placeId: e['placeId']?.toString() ?? '',
              description: e['description']?.toString() ?? '',
            ),
          )
          .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
          .toList();
      return PlacesSearchResult(suggestions: suggestions);
    } on DioException catch (e) {
      return PlacesSearchResult(
        suggestions: const [],
        errorMessage: messageFromDio(e),
      );
    }
  }

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final result = await search(input);
    return result.suggestions;
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
      final latD = lat.toDouble();
      final lngD = lng.toDouble();
      if (!isUsableGhanaLocation(latD, lngD)) return null;
      final address = data['address']?.toString().trim() ?? '';
      final label = await resolveAddressLabel(
        latD,
        lngD,
        existing: address,
      );
      return LocationPoint(address: label, lat: latD, lng: lngD);
    } on DioException {
      return null;
    }
  }

  /// Geocode a shop name + address when the vendor row has no lat/lng.
  Future<LocationPoint?> geocodeVendor({
    required String name,
    String? address,
    String? region,
  }) async {
    final parts = <String>[
      if (name.trim().isNotEmpty) name.trim(),
      if (address != null && address.trim().isNotEmpty) address.trim(),
      if (region != null && region.trim().isNotEmpty) region.trim(),
      'Ghana',
    ];
    final query = parts.join(', ');
    if (query.length < 4) return null;
    final result = await search(query);
    if (result.suggestions.isEmpty) return null;
    return placeDetails(result.suggestions.first.placeId);
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
      if (looksLikeCoordinates(address)) return null;
      return address;
    } on DioException {
      return null;
    }
  }

  Future<String?> _reverseGeocodeOnDevice(double lat, double lng) async {
    if (kIsWeb) return null;
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = <String>[
        if (p.name != null && p.name!.trim().isNotEmpty && p.name != p.street) p.name!,
        if (p.street != null && p.street!.trim().isNotEmpty) p.street!,
        if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) p.subLocality!,
        if (p.locality != null && p.locality!.trim().isNotEmpty) p.locality!,
        if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty)
          p.administrativeArea!,
        if (p.country != null && p.country!.trim().isNotEmpty) p.country!,
      ];
      final seen = <String>{};
      final unique = parts.where((s) => seen.add(s.toLowerCase())).toList();
      final label = unique.join(', ').trim();
      if (label.isEmpty || looksLikeCoordinates(label)) return null;
      return label;
    } catch (_) {
      return null;
    }
  }

  Future<String> resolveAddressLabel(
    double lat,
    double lng, {
    String? existing,
  }) async {
    final trimmed = existing?.trim() ?? '';
    if (trimmed.isNotEmpty && !needsAddressResolution(trimmed)) {
      return trimmed;
    }

    final fromApi = await reverseGeocode(lat, lng);
    if (fromApi != null && !looksLikeCoordinates(fromApi)) return fromApi;

    final fromDevice = await _reverseGeocodeOnDevice(lat, lng);
    if (fromDevice != null && !looksLikeCoordinates(fromDevice)) return fromDevice;

    return displayLocationLabel(existing, lat, lng);
  }
}
