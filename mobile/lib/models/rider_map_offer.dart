import 'location_point.dart';
import 'order.dart';
import 'vendor.dart';
import '../shared/rider_trip.dart';

/// Pickup / drop-off coordinates for showing a job on the driver map.
class RiderMapOffer {
  const RiderMapOffer({
    required this.orderId,
    required this.order,
    this.pickup,
    this.dropoff,
    this.selected = false,
  });

  final String orderId;
  final Order order;
  final LocationPoint? pickup;
  final LocationPoint? dropoff;
  final bool selected;

  bool get hasMap =>
      (pickup?.hasCoords ?? false) || (dropoff?.hasCoords ?? false);
}

RiderMapOffer riderMapOfferFromOrder(
  Order order,
  List<Vendor> vendors, {
  bool selected = false,
}) {
  LocationPoint? pickup;
  final pu = pickupCoordsForOrder(order, vendors);
  if (pu != null && hasValidCoords(pu.lat, pu.lng)) {
    pickup = LocationPoint(address: pu.label, lat: pu.lat, lng: pu.lng);
  }
  LocationPoint? dropoff;
  final drop = dropoffCoords(order);
  if (drop != null && hasValidCoords(drop.lat, drop.lng)) {
    dropoff = LocationPoint(address: drop.label, lat: drop.lat, lng: drop.lng);
  }
  return RiderMapOffer(
    orderId: order.id,
    order: order,
    pickup: pickup,
    dropoff: dropoff,
    selected: selected,
  );
}

List<RiderMapOffer> riderMapOffersFromOrders(
  List<Order> orders,
  List<Vendor> vendors, {
  String? selectedOrderId,
}) {
  return orders
      .map(
        (o) => riderMapOfferFromOrder(
          o,
          vendors,
          selected: o.id == selectedOrderId,
        ),
      )
      .where((o) => o.hasMap)
      .toList();
}
