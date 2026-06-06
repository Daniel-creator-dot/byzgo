import '../models/location_point.dart';
import '../models/order.dart';
import 'rider_trip.dart';

/// Customer-facing trip copy and progress — mirrors web `tripUi.tsx`.
class CustomerTripStep {
  const CustomerTripStep({
    required this.label,
    required this.active,
    this.current = false,
  });

  final String label;
  final bool active;
  final bool current;
}

bool customerCanShowDeliveryPin(Order order) {
  if (order.status != 'arrived') return false;
  if (order.paymentStatus == 'paid') return true;
  final ack = order.customerPaymentAck;
  return ack == 'cash' || ack == 'wallet' || ack == 'paystack';
}

bool customerIsSearchingBiker(Order order) {
  if (order.riderId != null) return false;
  return const {'pending', 'ready', 'preparing'}.contains(order.status);
}

/// Bolt/Yango-style countdown label for the live ETA pill.
String customerEtaCountdownLabel(Order order, {bool searching = false}) {
  if (searching || customerIsSearchingBiker(order)) {
    return 'est. pickup';
  }
  if (order.status == 'picked_up') return 'to you';
  if (order.status == 'arrived') return 'arrived';
  if (customerOrderHasShopPickup(order) &&
      const {'ready', 'preparing', 'pending'}.contains(order.status)) {
    return 'to shop';
  }
  return 'to pickup';
}

String customerSearchWaitSubline({
  required int nearbyCount,
  int? pickupMinutes,
  String? pickupPhrase,
}) {
  if (pickupMinutes != null && pickupMinutes > 0) {
    final est = pickupPhrase?.trim().isNotEmpty == true
        ? pickupPhrase!
        : 'about $pickupMinutes min';
    if (nearbyCount > 0) {
      return 'Nearest biker $est to pickup · matching your request';
    }
    return 'Typical wait $est — matching your request';
  }
  if (nearbyCount > 0) {
    return '$nearbyCount biker${nearbyCount == 1 ? '' : 's'} nearby — confirming your request';
  }
  return 'Matching you with the nearest available biker…';
}

/// Shop order: rider collects items at vendor before delivery.
bool customerOrderHasShopPickup(Order order) {
  return order.vendorId.trim().isNotEmpty;
}

String customerShopLabel(Order order) {
  final name = order.vendorName?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final pickup = order.pickupAddress?.trim() ?? order.pickup?.trim() ?? '';
  if (pickup.isNotEmpty) {
    return pickup.length > 48 ? '${pickup.substring(0, 45)}…' : pickup;
  }
  return 'the shop';
}

bool customerNeedsPayment(Order order) {
  return order.status == 'arrived' &&
      order.paymentStatus != 'paid' &&
      (order.customerPaymentAck == null || order.customerPaymentAck!.isEmpty);
}

/// Before pickup — includes courier trips that start as `ready`.
bool customerCanCancelOrder(Order order) {
  if (['delivered', 'cancelled', 'picked_up', 'arrived'].contains(order.status)) {
    return false;
  }
  return const {'pending', 'ready', 'preparing', 'scheduled'}.contains(order.status);
}

/// Stale trips should not block booking a new delivery.
bool customerTripBlocksNewBooking(Order order) {
  if (['delivered', 'cancelled', 'scheduled'].contains(order.status)) return false;
  try {
    final created = DateTime.parse(order.createdAt).toUtc();
    final age = DateTime.now().toUtc().difference(created);
    if (order.status == 'arrived' && age.inHours >= 2) return false;
    if (const {'ready', 'pending', 'preparing'}.contains(order.status) &&
        (order.riderId == null || order.riderId!.isEmpty) &&
        age.inDays >= 1) {
      return false;
    }
    if (age.inDays >= 7) return false;
  } catch (_) {}
  return true;
}

bool customerCanConfirmReceived(Order order) {
  return order.status == 'arrived' && !customerNeedsPayment(order);
}

String customerTripHeadline(Order order) {
  final shop = customerOrderHasShopPickup(order);
  switch (order.status) {
    case 'delivered':
      return 'Delivered';
    case 'arrived':
      return 'Driver has arrived';
    case 'picked_up':
      return shop ? 'Picked up — on the way' : 'On the way to you';
    case 'ready':
      if (order.riderId != null) {
        return shop ? 'Rider heading to shop' : 'Biker en route to pickup';
      }
      return shop ? 'Finding a rider for your shop order…' : 'Finding a biker nearby…';
    case 'preparing':
      if (order.riderId != null && shop) return 'Rider heading to shop';
      return order.riderId != null ? 'Biker found' : 'Preparing';
    case 'scheduled':
      return 'Scheduled delivery';
    case 'pending':
      if (order.riderId != null) {
        return shop ? 'Rider heading to shop' : 'Biker found';
      }
      return shop ? 'Finding a rider for your shop order…' : 'Finding a biker nearby…';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Updating…';
  }
}

/// Where the assigned biker is driving toward (for ETA).
LocationPoint? customerRiderNavTarget(Order order) {
  if (order.riderId == null) return null;
  if (['picked_up', 'arrived'].contains(order.status)) {
    if (order.lat != null &&
        order.lng != null &&
        hasValidCoords(order.lat!, order.lng!)) {
      return LocationPoint(
        address: order.address,
        lat: order.lat!,
        lng: order.lng!,
      );
    }
    return null;
  }
  if (order.pickupLat != null &&
      order.pickupLng != null &&
      hasValidCoords(order.pickupLat!, order.pickupLng!)) {
    return LocationPoint(
      address: order.pickupAddress ?? order.pickup ?? '',
      lat: order.pickupLat!,
      lng: order.pickupLng!,
    );
  }
  return null;
}

String customerTripSubline(Order order, {String? etaPhrase}) {
  final shopLabel = customerOrderHasShopPickup(order) ? customerShopLabel(order) : '';
  if (etaPhrase != null && etaPhrase.isNotEmpty && order.riderId != null) {
    if (['picked_up', 'arrived', 'ready', 'preparing', 'pending'].contains(order.status)) {
      return etaPhrase;
    }
  }
  switch (order.status) {
    case 'delivered':
      return 'Thanks for riding with BytzGO';
    case 'arrived':
      if (customerNeedsPayment(order)) {
        return 'Complete payment to unlock your delivery PIN';
      }
      return 'Share your PIN with the driver to finish';
    case 'picked_up':
      if (customerOrderHasShopPickup(order)) {
        return 'Collected at ${customerShopLabel(order)} — heading to your address';
      }
      return 'Your package is on the move';
    case 'ready':
      if (order.riderId != null) {
        if (customerOrderHasShopPickup(order)) {
          return 'Your rider is going to $shopLabel to pick up your order';
        }
        return 'Your biker is heading to the pickup point';
      }
      return customerOrderHasShopPickup(order)
          ? 'We\'re matching a rider to collect from the shop'
          : 'We\'re matching you with the nearest biker';
    case 'pending':
      if (order.riderId != null) {
        if (customerOrderHasShopPickup(order)) {
          return 'Your rider is going to $shopLabel to pick up your order';
        }
        return 'Biker assigned — waiting at pickup';
      }
      return customerOrderHasShopPickup(order)
          ? 'We\'re matching a rider to collect from the shop'
          : 'We\'re matching you with the nearest biker';
    default:
      return '';
  }
}

int _tripProgressIndex(Order order) {
  if (order.status == 'cancelled') return -1;
  if (order.status == 'delivered') return 5;
  if (order.status == 'arrived') return 4;
  if (order.status == 'picked_up') return 3;
  if (order.riderId != null &&
      ['ready', 'preparing', 'pending'].contains(order.status)) {
    return customerOrderHasShopPickup(order) ? 2 : 1;
  }
  if (order.riderId != null) return 1;
  return 0;
}

List<CustomerTripStep> customerTripSteps(Order order) {
  if (order.status == 'cancelled') {
    return const [
      CustomerTripStep(label: 'Cancelled', active: true, current: true),
    ];
  }
  final idx = _tripProgressIndex(order);
  final shop = customerOrderHasShopPickup(order);
  final labels = [
    'Requested',
    'Rider found',
    shop ? 'At shop' : 'At pickup',
    'On the way',
    'Arrived',
    'Delivered',
  ];
  return List.generate(labels.length, (i) {
    return CustomerTripStep(
      label: labels[i],
      active: i <= idx,
      current: i == idx,
    );
  });
}

/// Bottom-sheet height fraction during live tracking — keeps the map visible and
/// leaves room for a pinned payment footer when the driver has arrived.
double customerTrackingSheetFraction(
  Order order, {
  bool embedded = false,
  bool searching = false,
}) {
  switch (order.status) {
    case 'delivered':
      return embedded ? 0.34 : 0.36;
    case 'arrived':
      return embedded ? 0.46 : 0.48;
    case 'cancelled':
      return 0.22;
    default:
      if (searching) return embedded ? 0.17 : 0.19;
      return embedded ? 0.22 : 0.24;
  }
}
