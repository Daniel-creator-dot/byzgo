import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_point.dart';
import '../shared/ghana_location.dart';

class LocationService {
  Future<bool> ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      await openAppSettings();
      return false;
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<LocationPoint?> getCurrentLocation() async {
    final ok = await ensurePermission();
    if (!ok) return null;

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    if (!isUsableGhanaLocation(pos.latitude, pos.longitude)) {
      final fallback = accraDefaultPoint(
        address: 'Accra, Ghana — set pickup on map',
      );
      return fallback;
    }

    return LocationPoint(
      address: '',
      lat: pos.latitude,
      lng: pos.longitude,
    );
  }

  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    );
  }
}
