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

/// Android emulator / iOS simulator default (Google HQ) — not usable for Ghana delivery.
bool isSimulatorDefaultLocation(double lat, double lng) {
  return (lat - 37.421998).abs() < 0.02 && (lng - (-122.084)).abs() < 0.02;
}

bool isUsableGhanaLocation(double lat, double lng) {
  return isInGhanaBounds(lat, lng) && !isSimulatorDefaultLocation(lat, lng);
}

LocationPoint accraDefaultPoint({String address = 'Accra, Ghana'}) {
  return LocationPoint(address: address, lat: ghanaCenterLat, lng: ghanaCenterLng);
}

/// Prefer a human label; never show raw coordinates in the UI.
String displayLocationLabel(String? address, double lat, double lng) {
  final a = address?.trim() ?? '';
  if (a.isNotEmpty && !looksLikeCoordinates(a)) return a;
  if (isInGhanaBounds(lat, lng)) return 'Pinned location, Ghana';
  return 'Selected on map';
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
