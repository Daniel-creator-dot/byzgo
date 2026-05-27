import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/maps_runtime_config.dart';
import '../../models/admin_overview.dart';
import '../../shared/ghana_location.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/ride_map_background.dart';

/// Fleet map for admin — online drivers as green markers, active trip as blue.
class AdminLiveMap extends StatefulWidget {
  const AdminLiveMap({
    super.key,
    required this.riders,
    this.selectedId,
    this.onRiderTap,
  });

  final List<AdminLiveRider> riders;
  final String? selectedId;
  final void Function(AdminLiveRider rider)? onRiderTap;

  @override
  State<AdminLiveMap> createState() => _AdminLiveMapState();
}

class _AdminLiveMapState extends State<AdminLiveMap> {
  GoogleMapController? _controller;

  bool get _useNativeMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (final r in widget.riders) {
      if (!r.hasLocation || r.lat == null || r.lng == null) continue;
      final onTrip = r.activeTrips > 0;
      markers.add(
        Marker(
          markerId: MarkerId(r.id),
          position: LatLng(r.lat!, r.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            !r.isOnline
                ? BitmapDescriptor.hueOrange
                : onTrip
                    ? BitmapDescriptor.hueAzure
                    : BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: r.name,
            snippet: r.isOnline
                ? (onTrip ? 'On trip · ${r.activeTrips} active' : 'Online · idle')
                : 'Offline',
          ),
          onTap: () => widget.onRiderTap?.call(r),
          zIndex: widget.selectedId == r.id ? 2 : 1,
        ),
      );
    }
    return markers;
  }

  void _fitBounds() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final points = widget.riders
        .where((r) => r.hasLocation && r.lat != null && r.lng != null)
        .map((r) => LatLng(r.lat!, r.lng!))
        .toList();
    if (points.isEmpty) {
      ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(
          const LatLng(ghanaCenterLat, ghanaCenterLng),
          11,
        ),
      );
      return;
    }
    if (points.length == 1) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }
    var sw = points.first;
    var ne = points.first;
    for (final p in points) {
      if (p.latitude < sw.latitude) sw = LatLng(p.latitude, sw.longitude);
      if (p.longitude < sw.longitude) sw = LatLng(sw.latitude, p.longitude);
      if (p.latitude > ne.latitude) ne = LatLng(p.latitude, ne.longitude);
      if (p.longitude > ne.longitude) ne = LatLng(ne.latitude, p.longitude);
    }
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: sw, northeast: ne),
      64,
    ));
  }

  @override
  void didUpdateWidget(covariant AdminLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != oldWidget.selectedId ||
        widget.riders.length != oldWidget.riders.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNativeMap) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const RideMapBackground(),
          Center(
            child: Text(
              'Map requires Android or iOS build',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      );
    }

    final online = widget.riders.where((r) => r.isOnline).length;
    final onMap = widget.riders.where((r) => r.hasLocation).length;

    context.watch<MapsRuntimeConfig>();

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(ghanaCenterLat, ghanaCenterLng),
            zoom: 11,
          ),
          markers: _buildMarkers(),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) {
            _controller = c;
            _fitBounds();
          },
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            child: IconButton(
              onPressed: _fitBounds,
              icon: const Icon(Icons.my_location, color: BytzGoTheme.accent, size: 22),
              tooltip: 'Fit all drivers',
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(BytzGoTheme.accent, 'Online ($online)'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFF38BDF8), 'On trip'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFFF59E0B), 'GPS ($onMap)'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
