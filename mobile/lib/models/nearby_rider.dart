import 'location_point.dart';
import '../shared/rider_trip.dart';

/// Online rider returned from `/api/riders/nearby` (nearest first).
class NearbyRider {
  const NearbyRider({
    required this.id,
    required this.lat,
    required this.lng,
    this.distanceKm,
  });

  final String id;
  final double lat;
  final double lng;
  final double? distanceKm;

  LocationPoint toLocationPoint() =>
      LocationPoint(address: 'Biker', lat: lat, lng: lng);

  factory NearbyRider.fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}') ?? 0;
    final lng = double.tryParse('${json['lng']}') ?? 0;
    return NearbyRider(
      id: json['id']?.toString() ?? '',
      lat: lat,
      lng: lng,
      distanceKm: double.tryParse('${json['distance_km'] ?? json['distanceKm']}'),
    );
  }

  bool get hasCoords => hasValidCoords(lat, lng);
}
