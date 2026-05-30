import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/maps_runtime_config.dart';

import '../../core/env.dart';
import '../../models/location_point.dart';
import '../../models/rider_map_offer.dart';
import '../../shared/delivery_pricing.dart';
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
    this.followRider = false,
    this.pulseGuide,
    this.showPulseGuide = false,
    this.padding = EdgeInsets.zero,
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
  /// Keep camera centered on the moving biker (in-app navigation).
  final bool followRider;
  /// Customer's live Pulse Guide™ position (overrides static pin while active).
  final LocationPoint? pulseGuide;
  final bool showPulseGuide;
  /// Insets so the camera keeps the route/markers (and Google logo) in the
  /// visible window above the bottom sheet and below the top HUDs.
  final EdgeInsets padding;

  @override
  State<RideGoogleMap> createState() => RideGoogleMapState();
}

enum MapPickMode { pickup, destination }

class RideGoogleMapState extends State<RideGoogleMap> {
  GoogleMapController? _controller;
  // Pulse/radar phase (0..1). Advanced by a throttled timer (~10fps) instead of
  // a 60fps ticker so we don't flood the native map with circle/marker updates
  // every frame (that caused severe rider-side lag when Pulse Guide was active).
  Timer? _radarTimer;
  double _radarT = 0.0;
  static const int _radarTickMs = 100;
  static const double _radarStep = _radarTickMs / 2200;
  DateTime? _lastBoundsFit;
  DateTime? _lastFollow;
  // Previous rider position + last camera heading so we can rotate the camera to
  // the rider's ACTUAL travel direction (where they're moving) instead of always
  // pointing at the target.
  LatLng? _lastFollowPos;
  double? _lastHeading;
  static const _accra = LatLng(ghanaCenterLat, ghanaCenterLng);

  @override
  void initState() {
    super.initState();
    if (_radarActive(widget)) _startRadar();
  }

  bool _radarActive(RideGoogleMap w) =>
      w.showSearchRadar ||
      w.showRiderApproachRadar ||
      w.showDriverIdleRadar ||
      w.showPulseGuide;

  void _startRadar() {
    if (_radarTimer != null) return;
    _radarTimer = Timer.periodic(
      const Duration(milliseconds: _radarTickMs),
      (_) {
        if (!mounted) return;
        setState(() => _radarT = (_radarT + _radarStep) % 1.0);
      },
    );
  }

  void _stopRadar() {
    _radarTimer?.cancel();
    _radarTimer = null;
    _radarT = 0.0;
  }

  @override
  void dispose() {
    _radarTimer?.cancel();
    super.dispose();
  }

  bool get _useNativeMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    context.watch<MapsRuntimeConfig>();
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
    final layers = _buildLayers(_radarT);

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: target, zoom: 13.5),
          padding: widget.padding,
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
                  'Maps unavailable — update the app or ask admin to configure Google Maps on the server.',
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

    if (widget.showPulseGuide &&
        widget.pulseGuide != null &&
        widget.pulseGuide!.hasCoords) {
      final pg = widget.pulseGuide!;
      markers.add(
        Marker(
          markerId: const MarkerId('pulse_guide'),
          position: LatLng(pg.lat, pg.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Pulse Guide™',
            snippet: 'Customer live location — follow this pulse',
          ),
          zIndexInt: 4,
        ),
      );
      final center = LatLng(pg.lat, pg.lng);
      for (var i = 0; i < 4; i++) {
        final phase = (radarT + i * 0.25) % 1.0;
        circles.add(
          Circle(
            circleId: CircleId('pulse_guide_$i'),
            center: center,
            radius: 8 + phase * 45,
            fillColor: const Color(0xFFEF4444).withValues(alpha: (1 - phase) * 0.35),
            strokeColor: const Color(0xFFEF4444).withValues(alpha: (1 - phase) * 0.85),
            strokeWidth: 2,
            zIndex: 5,
          ),
        );
      }
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
      final target =
          widget.riderNavTarget ?? widget.destination ?? widget.pickup;
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
    if (widget.followRider &&
        widget.riderPosition != null &&
        widget.riderPosition!.hasCoords) {
      await _followRiderCamera();
      return;
    }
    _lastBoundsFit = null;
    await _fitBounds();
  }

  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final rLat1 = lat1 * math.pi / 180;
    final rLat2 = lat2 * math.pi / 180;
    final dLon = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(rLat2);
    final x = math.cos(rLat1) * math.sin(rLat2) -
        math.sin(rLat1) * math.cos(rLat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double? _bearingTowardTarget() {
    final pos = widget.riderPosition;
    if (pos == null || !pos.hasCoords) return null;
    final t = widget.riderNavTarget ?? widget.destination ?? widget.pickup;
    if (t == null || !t.hasCoords) return null;
    return _bearing(pos.lat, pos.lng, t.lat, t.lng);
  }

  Future<void> _followRiderCamera() async {
    final pos = widget.riderPosition;
    if (pos == null || !pos.hasCoords) return;
    final now = DateTime.now();
    if (_lastFollow != null &&
        now.difference(_lastFollow!) < const Duration(seconds: 1)) {
      return;
    }
    _lastFollow = now;
    final c = _controller;
    if (c == null) return;
    final here = LatLng(pos.lat, pos.lng);
    // Prefer the rider's actual travel heading (movement direction). Only update
    // it once they've moved enough (~6 m) so the camera doesn't spin while idle.
    double? heading;
    final prev = _lastFollowPos;
    if (prev != null) {
      final movedKm = haversineDistanceKm(
        prev.latitude,
        prev.longitude,
        here.latitude,
        here.longitude,
      );
      if (movedKm > 0.006) {
        heading = _bearing(
          prev.latitude,
          prev.longitude,
          here.latitude,
          here.longitude,
        );
      }
    }
    // Fall back to last known heading, then to bearing toward the target.
    heading ??= _lastHeading ?? _bearingTowardTarget();
    _lastHeading = heading;
    _lastFollowPos = here;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: here,
          zoom: 17,
          tilt: 50,
          bearing: heading ?? 0,
        ),
      ),
    );
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
        widget.showDriverIdleRadar ||
        widget.showPulseGuide;
    final neededRadar = oldWidget.showSearchRadar ||
        oldWidget.showRiderApproachRadar ||
        oldWidget.showDriverIdleRadar ||
        oldWidget.showPulseGuide;
    if (needsRadar != neededRadar) {
      if (needsRadar) {
        _startRadar();
      } else {
        _stopRadar();
      }
    }
    if (widget.followRider &&
        widget.riderPosition != null &&
        widget.riderPosition!.hasCoords) {
      final moved = oldWidget.riderPosition == null ||
          !oldWidget.riderPosition!.hasCoords ||
          (widget.riderPosition!.lat - oldWidget.riderPosition!.lat).abs() >
              0.00005 ||
          (widget.riderPosition!.lng - oldWidget.riderPosition!.lng).abs() >
              0.00005;
      if (moved) {
        unawaited(_followRiderCamera());
        return;
      }
    }
    if (oldWidget.pickup != widget.pickup ||
        oldWidget.destination != widget.destination ||
        oldWidget.riderPosition != widget.riderPosition ||
        oldWidget.routePoints.length != widget.routePoints.length ||
        oldWidget.jobOffers.length != widget.jobOffers.length ||
        oldWidget.padding != widget.padding) {
      unawaited(_fitBounds());
    }
  }
}
