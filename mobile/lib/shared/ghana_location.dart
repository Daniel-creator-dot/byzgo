import '../models/location_point.dart';
import 'delivery_pricing.dart';

/// Ghana defaults — port of `src/lib/ghanaLocation.ts`.
const double ghanaCenterLat = 5.6037;
const double ghanaCenterLng = -0.1870;

const double ghanaSouth = 4.62;
const double ghanaWest = -3.26;
const double ghanaNorth = 11.18;
const double ghanaEast = 1.19;

bool isInGhanaBounds(double lat, double lng) {
  return lat >= ghanaSouth &&
      lat <= ghanaNorth &&
      lng >= ghanaWest &&
      lng <= ghanaEast;
}

bool looksLikeCoordinates(String address) {
  if (address.trim().isEmpty) return false;
  return RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(address.trim());
}

String formatCoordAddress(double lat, double lng) {
  return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

double courierFeeBetween(LocationPoint pickup, LocationPoint destination, double pricePerKm) {
  final km = haversineDistanceKm(
    pickup.lat,
    pickup.lng,
    destination.lat,
    destination.lng,
  );
  return deliveryFeeFromDistanceKm(km, pricePerKm);
}
