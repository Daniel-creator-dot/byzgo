import '../models/order.dart';

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

bool customerNeedsPayment(Order order) {
  return order.status == 'arrived' &&
      order.paymentStatus != 'paid' &&
      (order.customerPaymentAck == null || order.customerPaymentAck!.isEmpty);
}

String customerTripHeadline(Order order) {
  switch (order.status) {
    case 'delivered':
      return 'Delivered';
    case 'arrived':
      return 'Driver has arrived';
    case 'picked_up':
      return 'On the way to you';
    case 'ready':
      if (order.riderId != null) {
        return 'Biker heading to pickup';
      }
      return 'Finding a biker nearby…';
    case 'preparing':
      return order.riderId != null ? 'Biker found' : 'Preparing';
    case 'pending':
      if (order.riderId != null) return 'Biker found';
      return 'Finding a biker nearby…';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Updating…';
  }
}

String customerTripSubline(Order order) {
  switch (order.status) {
    case 'delivered':
      return 'Thanks for riding with BytzGO';
    case 'arrived':
      if (customerNeedsPayment(order)) {
        return 'Complete payment to unlock your delivery PIN';
      }
      return 'Share your PIN with the driver to finish';
    case 'picked_up':
      return 'Your package is on the move';
    case 'ready':
    case 'pending':
      if (order.riderId != null) {
        return 'Rider is on the way to collect your package';
      }
      return 'We\'re matching you with the nearest biker';
    default:
      return '';
  }
}

int _tripProgressIndex(Order order) {
  if (order.status == 'delivered') return 5;
  if (order.status == 'arrived') return 4;
  if (order.status == 'picked_up') return 3;
  if (order.riderId != null &&
      ['ready', 'preparing', 'pending'].contains(order.status)) {
    return 2;
  }
  if (order.riderId != null) return 2;
  return 1;
}

List<CustomerTripStep> customerTripSteps(Order order) {
  final idx = _tripProgressIndex(order);
  const labels = [
    'Requested',
    'Biker found',
    'At pickup',
    'On the way',
    'Arrived',
    'Delivered',
  ];
  return List.generate(labels.length, (i) {
    return CustomerTripStep(
      label: labels[i],
      active: i <= idx,
      current: i == idx && order.status != 'delivered',
    );
  });
}
