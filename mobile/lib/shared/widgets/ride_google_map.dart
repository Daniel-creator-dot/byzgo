import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../models/location_point.dart';
import '../../shared/ghana_location.dart';
import '../theme.dart';
import 'ride_map_background.dart';

/// Google Map for ride-hail UI; painted fallback on web only.
class RideGoogleMap extends StatefulWidget {
  const RideGoogleMap({
    super.key,
    this.pickup,
    this.destination,
    this.riderPosition,
    this.onMapTap,
    this.mapPickMode,
    this.showRoute = false,
  });

  final LocationPoint? pickup;
  final LocationPoint? destination;
  final LocationPoint? riderPosition;
  final void Function(double lat, double lng)? onMapTap;
  final MapPickMode? mapPickMode;
  final bool showRoute;

  @override
  State<RideGoogleMap> createState() => _RideGoogleMapState();
}

enum MapPickMode { pickup, destination }

class _RideGoogleMapState extends State<RideGoogleMap> {
  GoogleMapController? _controller;
  static const _accra = LatLng(ghanaCenterLat, ghanaCenterLng);

  bool get _useNativeMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (!_useNativeMap) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const RideMapBackground(),
          if (widget.showRoute) const MapRouteArc(),
        ],
      );
    }

    final markers = <Marker>{};
    final polylines = <Polyline>{};

    if (widget.pickup != null && widget.pickup!.hasCoords) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(widget.pickup!.lat, widget.pickup!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Pickup', snippet: widget.pickup!.address),
        ),
      );
    }

    if (widget.destination != null && widget.destination!.hasCoords) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(widget.destination!.lat, widget.destination!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'Drop-off',
            snippet: widget.destination!.address,
          ),
        ),
      );
    }

    if (widget.riderPosition != null && widget.riderPosition!.hasCoords) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: LatLng(widget.riderPosition!.lat, widget.riderPosition!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'Rider'),
        ),
      );
    }

    if (widget.showRoute &&
        widget.pickup != null &&
        widget.destination != null &&
        widget.pickup!.hasCoords &&
        widget.destination!.hasCoords) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: BytzGoTheme.accent,
          width: 5,
          points: [
            LatLng(widget.pickup!.lat, widget.pickup!.lng),
            LatLng(widget.destination!.lat, widget.destination!.lng),
          ],
        ),
      );
    }

    final target = _cameraTarget();

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: target, zoom: 13.5),
          onMapCreated: (c) {
            _controller = c;
            _fitBounds();
          },
          markers: markers,
          polylines: polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onTap: widget.onMapTap == null
              ? null
              : (pos) => widget.onMapTap!(pos.latitude, pos.longitude),
        ),
        if (!Env.hasGoogleMaps)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Maps key missing in Dart — run: .\\scripts\\sync_maps_key.ps1',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  LatLng _cameraTarget() {
    if (widget.pickup != null && widget.pickup!.hasCoords) {
      return LatLng(widget.pickup!.lat, widget.pickup!.lng);
    }
    if (widget.destination != null && widget.destination!.hasCoords) {
      return LatLng(widget.destination!.lat, widget.destination!.lng);
    }
    return _accra;
  }

  Future<void> _fitBounds() async {
    final c = _controller;
    if (c == null) return;
    final points = <LatLng>[];
    if (widget.pickup?.hasCoords == true) {
      points.add(LatLng(widget.pickup!.lat, widget.pickup!.lng));
    }
    if (widget.destination?.hasCoords == true) {
      points.add(LatLng(widget.destination!.lat, widget.destination!.lng));
    }
    if (points.length < 2) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  void didUpdateWidget(covariant RideGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickup != widget.pickup ||
        oldWidget.destination != widget.destination) {
      _fitBounds();
    }
  }
}
