import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/maps_runtime_config.dart';
import '../../models/vendor.dart';
import '../ghana_location.dart';
import '../shop_categories.dart';
import '../theme.dart';

/// Map of popular shop pins in Accra (Restaurants / Food tabs).
class AccraShopsMap extends StatelessWidget {
  const AccraShopsMap({
    super.key,
    required this.vendors,
    required this.categoryId,
    this.selectedVendorId,
    this.onVendorTap,
    this.height = 220,
  });

  final List<Vendor> vendors;
  final String categoryId;
  final String? selectedVendorId;
  final ValueChanged<Vendor>? onVendorTap;
  final double height;

  static bool showMapForCategory(String categoryId) =>
      categoryId == 'restaurant' ||
      categoryId == 'food' ||
      categoryId == 'groceries';

  @override
  Widget build(BuildContext context) {
    final pins = vendors
        .where((v) => v.lat != null && v.lng != null)
        .toList();
    if (!showMapForCategory(categoryId) || pins.isEmpty) {
      return const SizedBox.shrink();
    }

    final cat = ShopCategory.byId(categoryId);
    final markers = <Marker>{};
    for (var i = 0; i < pins.length; i++) {
      final v = pins[i];
      final selected = v.id == selectedVendorId;
      markers.add(
        Marker(
          markerId: MarkerId(v.id),
          position: LatLng(v.lat!, v.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            selected
                ? BitmapDescriptor.hueGreen
                : categoryId == 'restaurant'
                    ? BitmapDescriptor.hueRed
                    : categoryId == 'groceries'
                        ? BitmapDescriptor.hueGreen
                        : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: v.name,
            snippet: v.phone ?? v.address ?? 'Tap for menu',
          ),
          onTap: onVendorTap == null ? null : () => onVendorTap!(v),
        ),
      );
    }

    final center = _centerFor(pins);

    context.watch<MapsRuntimeConfig>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(Icons.map_outlined, size: 18, color: cat?.accent ?? BytzGoTheme.brandBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${pins.length} popular places on the map',
                  style: BytzGoTheme.sheetBody(13).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Google Maps',
                style: BytzGoTheme.sheetBody(11).copyWith(color: BytzGoTheme.sheetMuted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: height,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 12.5),
                markers: markers,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  LatLng _centerFor(List<Vendor> pins) {
    if (pins.isEmpty) return const LatLng(ghanaCenterLat, ghanaCenterLng);
    var lat = 0.0;
    var lng = 0.0;
    for (final v in pins) {
      lat += v.lat!;
      lng += v.lng!;
    }
    return LatLng(lat / pins.length, lng / pins.length);
  }
}
