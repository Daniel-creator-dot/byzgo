import 'package:flutter/material.dart';

import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../models/rider_map_offer.dart';
import '../../models/vendor.dart';
import '../../shared/pulse_guide.dart';
import '../../shared/rider_trip.dart';
import '../../shared/widgets/ride_google_map.dart';

/// Driver map — GPS, open job pins, active trip route.
class RiderDriveMapLayer extends StatefulWidget {
  const RiderDriveMapLayer({
    super.key,
    required this.riderPosition,
    required this.isOnline,
    required this.availableOrders,
    required this.vendors,
    this.activeOrder,
    this.incomingOrder,
    this.previewOrderId,
    this.showRoute = false,
    this.routePoints = const [],
    this.followRider = false,
    this.mapPadding = EdgeInsets.zero,
  });

  final ValueNotifier<LocationPoint?> riderPosition;
  final bool isOnline;
  final List<Order> availableOrders;
  final List<Vendor> vendors;
  final Order? activeOrder;
  final Order? incomingOrder;
  final String? previewOrderId;
  final bool showRoute;
  final List<LocationPoint> routePoints;
  final bool followRider;
  final EdgeInsets mapPadding;

  @override
  State<RiderDriveMapLayer> createState() => RiderDriveMapLayerState();
}

class RiderDriveMapLayerState extends State<RiderDriveMapLayer> {
  final _mapKey = GlobalKey<RideGoogleMapState>();

  void fitAllMarkers() => _mapKey.currentState?.fitAllMarkers();

  LocationPoint? _stopPickup(Order? order) {
    if (order == null) return null;
    final stop = pickupCoordsForOrder(order, widget.vendors);
    if (stop == null || !hasValidCoords(stop.lat, stop.lng)) return null;
    return LocationPoint(address: stop.label, lat: stop.lat, lng: stop.lng);
  }

  LocationPoint? _stopDropoff(Order? order) {
    if (order == null) return null;
    final stop = dropoffCoords(order);
    if (stop == null || !hasValidCoords(stop.lat, stop.lng)) return null;
    return LocationPoint(address: stop.label, lat: stop.lat, lng: stop.lng);
  }

  Order? get _focusOrder {
    if (widget.activeOrder != null) return widget.activeOrder;
    if (widget.incomingOrder != null) return widget.incomingOrder;
    final id = widget.previewOrderId;
    if (id == null) return null;
    for (final o in widget.availableOrders) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final focus = _focusOrder;
    final idleOnMap = widget.isOnline &&
        widget.activeOrder == null &&
        widget.incomingOrder == null;

    final selectedId = widget.previewOrderId ??
        widget.incomingOrder?.id ??
        widget.activeOrder?.id;

    final offers = riderMapOffersFromOrders(
      widget.availableOrders,
      widget.vendors,
      selectedOrderId: selectedId,
    );

    final pickup = _stopPickup(focus) ??
        (offers.isNotEmpty && selectedId != null
            ? offers
                .where((o) => o.orderId == selectedId)
                .map((o) => o.pickup)
                .firstWhere((p) => p != null, orElse: () => null)
            : null);

    final destination = _stopDropoff(focus) ??
        (offers.isNotEmpty && selectedId != null
            ? offers
                .where((o) => o.orderId == selectedId)
                .map((o) => o.dropoff)
                .firstWhere((d) => d != null, orElse: () => null)
            : null);

    LocationPoint? navTarget;
    if (focus != null) {
      final stop = navigationTarget(focus, widget.vendors);
      if (stop != null && hasValidCoords(stop.lat, stop.lng)) {
        navTarget = LocationPoint(
          address: stop.label,
          lat: stop.lat,
          lng: stop.lng,
        );
      }
    }

    final hasDrivingRoute = widget.routePoints.length >= 2;

    LocationPoint? pulseGuide;
    final active = widget.activeOrder;
    if (active != null &&
        isPulseGuideActive(active) &&
        active.pulseGuideLat != null &&
        active.pulseGuideLng != null) {
      pulseGuide = LocationPoint(
        address: 'Pulse Guide™',
        lat: active.pulseGuideLat!,
        lng: active.pulseGuideLng!,
      );
    }

    return ValueListenableBuilder<LocationPoint?>(
      valueListenable: widget.riderPosition,
      builder: (context, pos, _) {
        return RideGoogleMap(
          key: _mapKey,
          pickup: pickup,
          destination: destination,
          riderPosition: pos,
          riderNavTarget: navTarget,
          routePoints: widget.routePoints,
          showRoute: widget.showRoute,
          showLiveRiderRoute: widget.showRoute &&
              widget.activeOrder != null &&
              !hasDrivingRoute &&
              pos != null &&
              navTarget != null,
          showDriverIdleRadar: idleOnMap,
          jobOffers: idleOnMap || widget.incomingOrder == null
              ? offers
              : riderMapOffersFromOrders(
                  widget.incomingOrder != null
                      ? [widget.incomingOrder!]
                      : const [],
                  widget.vendors,
                  selectedOrderId: selectedId,
                ),
          followRider: widget.followRider,
          pulseGuide: pulseGuide,
          showPulseGuide: pulseGuide != null,
          padding: widget.mapPadding,
        );
      },
    );
  }
}
