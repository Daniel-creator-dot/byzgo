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
  final a = address.trim();
  if (a.isEmpty) return false;
  // 5.6037, -0.1870 or 5.6037 -0.1870
  if (RegExp(r'^-?\d+(\.\d+)?\s*[, ]\s*-?\d+(\.\d+)?$').hasMatch(a)) {
    return true;
  }
  // Short strings that are mostly a lat/lng pair (saved profile coords, etc.)
  if (a.length <= 48 &&
      RegExp(r'-?\d+\.\d+\s*[, ]\s*-?\d+\.\d+').hasMatch(a)) {
    return true;
  }
  return false;
}

/// True when we should call reverse geocode instead of showing the stored string.
bool needsAddressResolution(String? address) {
  final a = address?.trim() ?? '';
  if (a.isEmpty) return true;
  if (looksLikeCoordinates(a)) return true;
  final lower = a.toLowerCase();
  if (lower == 'finding address…' ||
      lower == 'pinned location, ghana' ||
      lower == 'selected on map' ||
      lower == 'current location') {
    return true;
  }
  return false;
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
  if (a.isNotEmpty && !looksLikeCoordinates(a) && !needsAddressResolution(a)) {
    return a;
  }
  if (isInGhanaBounds(lat, lng)) return 'Current location';
  return 'Selected on map';
}

/// Market emphasis for Accra-area ride hub defaults (all modes stay visible).
enum AccraRideEmphasis { okada, package }

class AccraRideZone {
  const AccraRideZone({
    required this.id,
    required this.emphasis,
    required this.aliases,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  final String id;
  final AccraRideEmphasis emphasis;
  final List<String> aliases;
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  bool get hasBox =>
      south != null && west != null && north != null && east != null;

  bool contains(double lat, double lng) {
    if (!hasBox) return false;
    return lat >= south! && lat <= north! && lng >= west! && lng <= east!;
  }
}

/// Okada-first: Kasoa and peri-urban west/north Accra corridors.
const List<AccraRideZone> accraOkadaFirstZones = [
  AccraRideZone(
    id: 'kasoa',
    emphasis: AccraRideEmphasis.okada,
    aliases: ['kasoa', 'kasoa new town', 'ofaakor'],
    south: 5.48,
    west: -0.50,
    north: 5.58,
    east: -0.35,
  ),
  AccraRideZone(
    id: 'weija_mallam',
    emphasis: AccraRideEmphasis.okada,
    aliases: ['weija', 'mallam', 'mallam junction', 'gbawe', 'bortianor'],
    south: 5.54,
    west: -0.36,
    north: 5.62,
    east: -0.26,
  ),
  AccraRideZone(
    id: 'amasaman',
    emphasis: AccraRideEmphasis.okada,
    aliases: ['amasaman', 'amasan', 'amassaman'],
    south: 5.66,
    west: -0.36,
    north: 5.76,
    east: -0.26,
  ),
  AccraRideZone(
    id: 'pokuase_ofankor',
    emphasis: AccraRideEmphasis.okada,
    aliases: ['pokuase', 'ofankor', 'taifa', 'kwabenya', 'achimota forest'],
    south: 5.64,
    west: -0.30,
    north: 5.74,
    east: -0.22,
  ),
];

/// Delivery-first: central / elite Accra package-courier demand.
const List<AccraRideZone> accraPackageFirstZones = [
  AccraRideZone(
    id: 'cantonment_osu_labone',
    emphasis: AccraRideEmphasis.package,
    aliases: ['cantonment', 'osu', 'labone', 'labadi'],
    south: 5.545,
    west: -0.185,
    north: 5.585,
    east: -0.155,
  ),
  AccraRideZone(
    id: 'asylum_ridge_central',
    emphasis: AccraRideEmphasis.package,
    aliases: [
      'asylum down',
      'asyllum',
      'asylumdown',
      'ridge',
      'accra central',
      'adabraka',
    ],
    south: 5.545,
    west: -0.220,
    north: 5.575,
    east: -0.185,
  ),
  AccraRideZone(
    id: 'airport_roman_dzorwulu',
    emphasis: AccraRideEmphasis.package,
    aliases: [
      'airport residential',
      'airport west',
      'roman ridge',
      'dzorwulu',
    ],
    south: 5.585,
    west: -0.210,
    north: 5.630,
    east: -0.155,
  ),
  AccraRideZone(
    id: 'east_legon',
    emphasis: AccraRideEmphasis.package,
    aliases: ['east legon', 'eastlegon', 'shiashie'],
    south: 5.620,
    west: -0.165,
    north: 5.670,
    east: -0.125,
  ),
  AccraRideZone(
    id: 'spintex',
    emphasis: AccraRideEmphasis.package,
    aliases: ['spintex', 'lashibi', 'baatsona'],
    south: 5.620,
    west: -0.120,
    north: 5.670,
    east: -0.040,
  ),
];

const List<AccraRideZone> accraRideZones = [
  ...accraOkadaFirstZones,
  ...accraPackageFirstZones,
];

bool _aliasInText(String haystack, String alias) {
  final a = alias.trim().toLowerCase();
  if (a.isEmpty) return false;
  final h = haystack.toLowerCase();
  if (a.contains(' ')) return h.contains(a);
  return RegExp('\\b${RegExp.escape(a)}\\b').hasMatch(h);
}

AccraRideZone? accraRideZoneFromText(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty || looksLikeCoordinates(t) || needsAddressResolution(t)) {
    return null;
  }
  for (final zone in accraRideZones) {
    for (final alias in zone.aliases) {
      if (_aliasInText(t, alias)) return zone;
    }
  }
  return null;
}

AccraRideZone? accraRideZoneFromCoords(double? lat, double? lng) {
  if (lat == null || lng == null) return null;
  if (!isUsableGhanaLocation(lat, lng)) return null;
  for (final zone in accraRideZones) {
    if (zone.contains(lat, lng)) return zone;
  }
  return null;
}

/// Pickup address first, then user region (and profile address), then GPS.
AccraRideZone? resolveAccraRideZone({
  String? pickupAddress,
  String? userRegion,
  String? userAddress,
  double? lat,
  double? lng,
}) {
  return accraRideZoneFromText(pickupAddress) ??
      accraRideZoneFromText(userRegion) ??
      accraRideZoneFromText(userAddress) ??
      accraRideZoneFromCoords(lat, lng);
}

AccraRideEmphasis? accraRideEmphasis({
  String? pickupAddress,
  String? userRegion,
  String? userAddress,
  double? lat,
  double? lng,
}) {
  return resolveAccraRideZone(
    pickupAddress: pickupAddress,
    userRegion: userRegion,
    userAddress: userAddress,
    lat: lat,
    lng: lng,
  )?.emphasis;
}

double courierFeeBetween(
  LocationPoint pickup,
  LocationPoint destination,
  double pricePerKm, {
  double? minFee,
  double? maxFee,
}) {
  final km = haversineDistanceKm(
    pickup.lat,
    pickup.lng,
    destination.lat,
    destination.lng,
  );
  return deliveryFeeFromDistanceKm(
    km,
    pricePerKm,
    min: minFee,
    max: maxFee,
  );
}
