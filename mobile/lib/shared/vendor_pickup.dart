import '../core/places_service.dart';
import '../models/location_point.dart';
import '../models/vendor.dart';
import 'ghana_location.dart';

/// Shop pickup point from vendor row or geocoded name/address.
Future<LocationPoint?> resolveVendorPickup(
  Vendor vendor,
  PlacesService places,
) async {
  if (vendor.lat != null &&
      vendor.lng != null &&
      isUsableGhanaLocation(vendor.lat!, vendor.lng!)) {
    return LocationPoint(
      address: vendor.address?.trim().isNotEmpty == true
          ? vendor.address!.trim()
          : vendor.name,
      lat: vendor.lat!,
      lng: vendor.lng!,
    );
  }
  return places.geocodeVendor(
    name: vendor.name,
    address: vendor.address,
    region: vendor.region,
  );
}
