import 'package:url_launcher/url_launcher.dart';

import '../models/location_point.dart';
import '../models/order.dart';
import '../models/vendor.dart';

enum TripPhase { toPickup, toDropoff }

class TripStop {
  const TripStop({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String label;
}

bool hasValidCoords(double lat, double lng) {
  return lat.isFinite &&
      lng.isFinite &&
      lat.abs() > 0.001 &&
      lng.abs() > 0.001;
}

TripStop? dropoffCoords(Order order) {
  if (order.lat != null &&
      order.lng != null &&
      hasValidCoords(order.lat!, order.lng!)) {
    return TripStop(
      lat: order.lat!,
      lng: order.lng!,
      label: order.address.isNotEmpty ? order.address : 'Drop-off',
    );
  }
  if (order.address.trim().isNotEmpty) {
    return TripStop(lat: 0, lng: 0, label: order.address.trim());
  }
  return null;
}

TripStop? pickupCoordsForOrder(Order order, List<Vendor> vendors) {
  if (order.isCourier && order.pickupLat != null && order.pickupLng != null) {
    final label = order.pickupAddress ?? order.pickup ?? 'Pickup';
    return TripStop(
      lat: order.pickupLat!,
      lng: order.pickupLng!,
      label: label,
    );
  }
  Vendor? vendor;
  for (final v in vendors) {
    if (v.id == order.vendorId) {
      vendor = v;
      break;
    }
  }
  if (vendor == null) return null;
  if (vendor.lat != null &&
      vendor.lng != null &&
      hasValidCoords(vendor.lat!, vendor.lng!)) {
    return TripStop(
      lat: vendor.lat!,
      lng: vendor.lng!,
      label: vendor.name.isNotEmpty
          ? vendor.name
          : (vendor.address ?? 'Vendor'),
    );
  }
  if (vendor.address != null && vendor.address!.trim().isNotEmpty) {
    final label = vendor.name.isNotEmpty
        ? '${vendor.name}, ${vendor.address!.trim()}'
        : vendor.address!.trim();
    return TripStop(lat: 0, lng: 0, label: label);
  }
  if (vendor.name.isNotEmpty) {
    return TripStop(lat: 0, lng: 0, label: vendor.name);
  }
  return null;
}

TripPhase tripPhase(Order order) {
  return order.status == 'picked_up' || order.status == 'arrived'
      ? TripPhase.toDropoff
      : TripPhase.toPickup;
}

TripStop? navigationTarget(Order order, List<Vendor> vendors) {
  if (order.status == 'picked_up' || order.status == 'arrived') {
    return dropoffCoords(order);
  }
  return pickupCoordsForOrder(order, vendors);
}

String googleMapsNavUrl(double destLat, double destLng, {LocationPoint? origin}) {
  final params = <String, String>{
    'api': '1',
    'destination': '$destLat,$destLng',
    'travelmode': 'driving',
  };
  if (origin != null && hasValidCoords(origin.lat, origin.lng)) {
    params['origin'] = '${origin.lat},${origin.lng}';
  }
  return Uri(
    scheme: 'https',
    host: 'www.google.com',
    path: '/maps/dir/',
    queryParameters: params,
  ).toString();
}

String googleMapsSearchUrl(String query) {
  return Uri(
    scheme: 'https',
    host: 'www.google.com',
    path: '/maps/search/',
    queryParameters: {'api': '1', 'query': query},
  ).toString();
}

Future<bool> openTurnByTurnNavigation(
  TripStop target, {
  LocationPoint? origin,
}) async {
  final url = hasValidCoords(target.lat, target.lng)
      ? googleMapsNavUrl(target.lat, target.lng, origin: origin)
      : googleMapsSearchUrl(target.label);
  final uri = Uri.parse(url);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool isPaymentReady(Order order) {
  if (order.paymentStatus == 'paid') return true;
  final ack = order.customerPaymentAck;
  return ack == 'cash' || ack == 'wallet' || ack == 'paystack';
}

String formatCompleteError(String? message) {
  final m = (message ?? '').trim();
  if (m.isEmpty) return 'Could not complete delivery. Try again.';
  if (RegExp(r'waiting for customer', caseSensitive: false).hasMatch(m)) {
    return 'Customer must confirm payment first — then they share the 6-digit PIN.';
  }
  if (RegExp(r'invalid code', caseSensitive: false).hasMatch(m)) {
    return 'Wrong PIN. Ask the customer for the 6-digit code from their app.';
  }
  if (RegExp(r'mark arrived', caseSensitive: false).hasMatch(m)) {
    return 'Tap "I\'ve arrived" before completing delivery.';
  }
  return m;
}

int activeTripStep(Order order) {
  switch (order.status) {
    case 'ready':
      return 1;
    case 'picked_up':
      return 2;
    case 'arrived':
      return 3;
    default:
      return 4;
  }
}

/// Rider-facing trip progress — mirrors web `riderTripUi.tsx`.
class RiderTripStep {
  const RiderTripStep({
    required this.label,
    required this.active,
    this.current = false,
  });

  final String label;
  final bool active;
  final bool current;
}

List<RiderTripStep> riderTripSteps(Order order) {
  final step = activeTripStep(order);
  const labels = ['Accepted', 'Picked up', 'Arrived', 'Complete'];
  return List.generate(labels.length, (i) {
    return RiderTripStep(
      label: labels[i],
      active: i < step,
      current: i == step - 1 || (step == 0 && i == 0),
    );
  });
}

String riderTripHeadline(Order order) {
  switch (order.status) {
    case 'ready':
      return 'Head to pickup';
    case 'picked_up':
      return 'Head to drop-off';
    case 'arrived':
      return isPaymentReady(order) ? 'Enter customer PIN' : 'Waiting for payment';
    default:
      return 'Active delivery';
  }
}

String riderTripSubline(Order order, {String? navLabel}) {
  if (navLabel != null && navLabel.isNotEmpty) {
    return navLabel;
  }
  switch (order.status) {
    case 'ready':
      return 'Collect the order, then mark picked up';
    case 'picked_up':
      return 'Navigate to the customer';
    case 'arrived':
      if (!isPaymentReady(order)) {
        return 'Customer must confirm payment in the app';
      }
      return 'Ask for the 6-digit PIN to complete';
    default:
      return '';
  }
}

/// Bottom-sheet height during active delivery — keeps map visible; taller when
/// arrived so the PIN footer fits without scrolling.
double riderTrackingSheetFraction(Order order) {
  switch (order.status) {
    case 'arrived':
      return 0.44;
    case 'picked_up':
      return 0.22;
    case 'ready':
      return 0.24;
    default:
      return 0.26;
  }
}

bool isOfferableOrder(Order order) {
  if (order.riderId != null) return false;
  if (const {'cancelled', 'delivered', 'picked_up', 'arrived'}.contains(order.status)) {
    return false;
  }
  final offerableStatus = order.status == 'ready' ||
      (order.status == 'pending' &&
          order.vendorId.trim().isNotEmpty &&
          (order.orderType == 'food' || order.orderType == 'courier'));
  if (!offerableStatus) return false;
  if (order.expiresAt == null) return true;
  try {
    return DateTime.parse(order.expiresAt!).isAfter(DateTime.now());
  } catch (_) {
    return true;
  }
}

int? offerSecondsRemaining(Order order) {
  if (order.expiresAt == null) return null;
  try {
    final secs =
        DateTime.parse(order.expiresAt!).difference(DateTime.now()).inSeconds;
    return secs < 0 ? 0 : secs;
  } catch (_) {
    return null;
  }
}
