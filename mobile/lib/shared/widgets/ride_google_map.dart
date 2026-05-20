import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../models/location_point.dart';
import '../../models/rider_map_offer.dart';
import '../../shared/ghana_location.dart';
import '../theme.dart';
import 'biker_search_radar.dart';
import 'live_trip_map_overlay.dart';
import 'ride_map_background.dart';

/// Google Map for ride-hail UI; painted fallback on web only.
class RideGoogleMap extends StatefulWidget {
  const RideGoogleMap({
    super.key,
    this.pickup,
    this.destination,
    this.riderPosition,
    this.nearbyRiders = const [],
    this.showSearchRadar = false,
    this.onMapTap,
    this.mapPickMode,
    this.showRoute = false,
    this.routePoints = const [],
    this.showLiveRiderRoute = false,
    this.showRiderApproachRadar = false,
    this.riderNavTarget,
    this.jobOffers = const [],
    this.showDriverIdleRadar = false,
  });

  final LocationPoint? pickup;
  final LocationPoint? destination;
  final LocationPoint? riderPosition;
  /// Online riders near pickup (while matching).
  final List<LocationPoint> nearbyRiders;
  final bool showSearchRadar;
  final void Function(double lat, double lng)? onMapTap;
  final MapPickMode? mapPickMode;
  final bool showRoute;
  /// Turn-by-turn polyline (e.g. from Directions API).
  final List<LocationPoint> routePoints;
  /// Rider → pickup or rider → drop-off while tracking.
  final bool showLiveRiderRoute;
  /// Pulsing rings on the assigned biker while they approach.
  final bool showRiderApproachRadar;
  /// Destination the biker is driving toward (for web overlay).
  final LocationPoint? riderNavTarget;
  /// Open jobs to plot on map (driver console).
  final List<RiderMapOffer> jobOffers;
  /// Pulse rings at driver GPS while waiting for jobs.
  final bool showDriverIdleRadar;

  @override
  State<RideGoogleMap> createState() => RideGoogleMapState();
}

enum MapPickMode { pickup, destination }

class RideGoogleMapState extends State<RideGoogleMap>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _controller;
  late final AnimationController _radarCtrl;
  DateTime? _lastBoundsFit;
  static const _accra = LatLng(ghanaCenterLat, ghanaCenterLng);

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.showSearchRadar ||
        widget.showRiderApproachRadar ||
        widget.showDriverIdleRadar) {
      _radarCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  bool get _useNativeMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (!_useNativeMap) {
      final center = widget.pickup;
      return Stack(
        fit: StackFit.expand,
        children: [
          const RideMapBackground(),
          if (widget.showRoute) const MapRouteArc(),
          if (widget.showSearchRadar &&
              center != null &&
              center.hasCoords)
            MapBikerSearchOverlay(
              centerLat: center.lat,
              centerLng: center.lng,
              nearbyRiders: widget.nearbyRiders,
            ),
          if (widget.showRiderApproachRadar &&
              widget.riderPosition != null &&
              widget.riderPosition!.hasCoords &&
              widget.riderNavTarget != null &&
              widget.riderNavTarget!.hasCoords)
            MapLiveRiderOverlay(
              rider: widget.riderPosition!,
              target: widget.riderNavTarget!,
              pickup: widget.pickup,
              destination: widget.destination,
            ),
        ],
      );
    }

    final target = _cameraTarget();

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _radarCtrl,
          builder: (context, _) {
            final layers = _buildLayers(_radarCtrl.value);
            return GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 13.5),
              onMapCreated: (c) {
                _controller = c;
                _fitBounds();
              },
              markers: layers.markers,
              polylines: layers.polylines,
              circles: layers.circles,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: widget.onMapTap == null
                  ? null
                  : (pos) => widget.onMapTap!(pos.latitude, pos.longitude),
            );
          },
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

  ({Set<Marker> markers, Set<Polyline> polylines, Set<Circle> circles}) _buildLayers(
    double radarT,
  ) {
    final markers = <Marker>{};
    final polylines = <Polyline>{};
    final circles = <Circle>{};

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
          infoWindow: InfoWindow(
            title: 'Your biker',
            snippet: widget.riderPosition!.address.isNotEmpty
                ? widget.riderPosition!.address
                : null,
          ),
          zIndexInt: 3,
        ),
      );
    }

    for (final offer in widget.jobOffers) {
      if (offer.pickup != null && offer.pickup!.hasCoords) {
        markers.add(
          Marker(
            markerId: MarkerId('offer_pu_${offer.orderId}'),
            position: LatLng(offer.pickup!.lat, offer.pickup!.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              offer.selected
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueGreen,
            ),
            alpha: offer.selected ? 1.0 : 0.75,
            infoWindow: InfoWindow(
              title: 'Pickup · #${offer.orderId.length > 4 ? offer.orderId.substring(offer.orderId.length - 4) : offer.orderId}',
              snippet: offer.pickup!.address,
            ),
            zIndexInt: offer.selected ? 2 : 1,
          ),
        );
      }
      if (offer.dropoff != null && offer.dropoff!.hasCoords) {
        markers.add(
          Marker(
            markerId: MarkerId('offer_drop_${offer.orderId}'),
            position: LatLng(offer.dropoff!.lat, offer.dropoff!.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            alpha: offer.selected ? 1.0 : 0.7,
            infoWindow: InfoWindow(
              title: 'Customer',
              snippet: offer.dropoff!.address,
            ),
            zIndexInt: offer.selected ? 2 : 0,
          ),
        );
      }
      if (offer.selected &&
          offer.pickup != null &&
          offer.dropoff != null &&
          offer.pickup!.hasCoords &&
          offer.dropoff!.hasCoords) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('offer_route_${offer.orderId}'),
            color: BytzGoTheme.accent,
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(12)],
            points: [
              LatLng(offer.pickup!.lat, offer.pickup!.lng),
              LatLng(offer.dropoff!.lat, offer.dropoff!.lng),
            ],
          ),
        );
      }
    }

    for (var i = 0; i < widget.nearbyRiders.length; i++) {
      final r = widget.nearbyRiders[i];
      if (!r.hasCoords) continue;
      markers.add(
        Marker(
          markerId: MarkerId('nearby_$i'),
          position: LatLng(r.lat, r.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Biker nearby'),
        ),
      );
    }

    if (widget.showSearchRadar &&
        widget.pickup != null &&
        widget.pickup!.hasCoords) {
      final center = LatLng(widget.pickup!.lat, widget.pickup!.lng);
      for (var i = 0; i < 3; i++) {
        final phase = (radarT + i * 0.33) % 1.0;
        circles.add(
          Circle(
            circleId: CircleId('radar_$i'),
            center: center,
            radius: 120 + phase * 520,
            fillColor: BytzGoTheme.accent.withValues(alpha: (1 - phase) * 0.12),
            strokeColor: BytzGoTheme.brandBlue.withValues(alpha: (1 - phase) * 0.45),
            strokeWidth: 2,
          ),
        );
      }
    }

    if (widget.showDriverIdleRadar &&
        widget.riderPosition != null &&
        widget.riderPosition!.hasCoords) {
      final center =
          LatLng(widget.riderPosition!.lat, widget.riderPosition!.lng);
      for (var i = 0; i < 3; i++) {
        final phase = (radarT + i * 0.33) % 1.0;
        circles.add(
          Circle(
            circleId: CircleId('driver_radar_$i'),
            center: center,
            radius: 150 + phase * 600,
            fillColor: BytzGoTheme.accent.withValues(alpha: (1 - phase) * 0.14),
            strokeColor: BytzGoTheme.accent.withValues(alpha: (1 - phase) * 0.5),
            strokeWidth: 2,
          ),
        );
      }
    }

    if (widget.showRiderApproachRadar &&
        widget.riderPosition != null &&
        widget.riderPosition!.hasCoords) {
      final riderCenter =
          LatLng(widget.riderPosition!.lat, widget.riderPosition!.lng);
      for (var i = 0; i < 3; i++) {
        final phase = (radarT + i * 0.33) % 1.0;
        circles.add(
          Circle(
            circleId: CircleId('rider_radar_$i'),
            center: riderCenter,
            radius: 80 + phase * 280,
            fillColor: BytzGoTheme.accent.withValues(alpha: (1 - phase) * 0.18),
            strokeColor: Colors.orange.withValues(alpha: (1 - phase) * 0.55),
            strokeWidth: 2,
          ),
        );
      }
    }

    final routeLine = <LatLng>[];
    if (widget.routePoints.length >= 2) {
      for (final p in widget.routePoints) {
        if (p.hasCoords) routeLine.add(LatLng(p.lat, p.lng));
      }
    } else if (widget.showRoute &&
        widget.pickup != null &&
        widget.destination != null &&
        widget.pickup!.hasCoords &&
        widget.destination!.hasCoords) {
      routeLine.add(LatLng(widget.pickup!.lat, widget.pickup!.lng));
      routeLine.add(LatLng(widget.destination!.lat, widget.destination!.lng));
    } else if (widget.showLiveRiderRoute &&
        widget.riderPosition != null &&
        widget.riderPosition!.hasCoords) {
      final target = widget.destination ?? widget.pickup;
      if (target != null && target.hasCoords) {
        routeLine.add(
          LatLng(widget.riderPosition!.lat, widget.riderPosition!.lng),
        );
        routeLine.add(LatLng(target.lat, target.lng));
      }
    }
    if (routeLine.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: widget.showLiveRiderRoute
              ? BytzGoTheme.brandBlue
              : BytzGoTheme.accent,
          width: widget.showLiveRiderRoute ? 6 : 5,
          points: routeLine,
        ),
      );
    }

    return (markers: markers, polylines: polylines, circles: circles);
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

  /// Re-frame map to pickup, drop-off, rider, and nearby bikers.
  Future<void> fitAllMarkers() async {
    _lastBoundsFit = null;
    await _fitBounds();
  }

  Future<void> _fitBounds() async {
    final now = DateTime.now();
    if (_lastBoundsFit != null &&
        now.difference(_lastBoundsFit!) < const Duration(seconds: 3)) {
      return;
    }
    _lastBoundsFit = now;
    final c = _controller;
    if (c == null) return;
    final points = <LatLng>[];
    if (widget.pickup?.hasCoords == true) {
      points.add(LatLng(widget.pickup!.lat, widget.pickup!.lng));
    }
    if (widget.destination?.hasCoords == true) {
      points.add(LatLng(widget.destination!.lat, widget.destination!.lng));
    }
    if (widget.riderPosition?.hasCoords == true) {
      points.add(LatLng(widget.riderPosition!.lat, widget.riderPosition!.lng));
    }
    for (final offer in widget.jobOffers) {
      if (offer.pickup?.hasCoords == true) {
        points.add(LatLng(offer.pickup!.lat, offer.pickup!.lng));
      }
      if (offer.dropoff?.hasCoords == true) {
        points.add(LatLng(offer.dropoff!.lat, offer.dropoff!.lng));
      }
    }
    for (final r in widget.nearbyRiders) {
      if (r.hasCoords) points.add(LatLng(r.lat, r.lng));
    }
    if (points.isEmpty) return;
    if (points.length < 2) {
      await c.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }
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
    final needsRadar = widget.showSearchRadar ||
        widget.showRiderApproachRadar ||
        widget.showDriverIdleRadar;
    final neededRadar = oldWidget.showSearchRadar ||
        oldWidget.showRiderApproachRadar ||
        oldWidget.showDriverIdleRadar;
    if (needsRadar != neededRadar) {
      if (needsRadar) {
        if (!_radarCtrl.isAnimating) _radarCtrl.repeat();
      } else {
        _radarCtrl.stop();
        _radarCtrl.reset();
      }
    }
    if (oldWidget.pickup != widget.pickup ||
        oldWidget.destination != widget.destination ||
        oldWidget.riderPosition != widget.riderPosition ||
        oldWidget.routePoints.length != widget.routePoints.length ||
        oldWidget.jobOffers.length != widget.jobOffers.length) {
      _fitBounds();
    }
  }
}
