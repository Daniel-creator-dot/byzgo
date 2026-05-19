class LocationPoint {
  const LocationPoint({
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String address;
  final double lat;
  final double lng;

  bool get hasCoords => lat != 0 && lng != 0;

  LocationPoint copyWith({String? address, double? lat, double? lng}) {
    return LocationPoint(
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  String toString() => '$address ($lat, $lng)';
}
