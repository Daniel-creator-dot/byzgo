import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/push_notification_service.dart';
import '../../models/order.dart';
import '../../shared/rider_trip.dart';
import 'incoming_ride_ring.dart';

/// Ring + wakelock + high-priority notification for an incoming delivery offer.
class IncomingRideAlert {
  IncomingRideAlert._();

  static String? _activeOrderId;

  static Future<void> raise(
    Order order, {
    bool showNotification = true,
  }) async {
    if (!isOfferableOrder(order)) return;
    if (_activeOrderId == order.id) {
      await IncomingRideRing.start();
      if (showNotification) {
        final pickup = order.pickupAddress?.trim().isNotEmpty == true
            ? order.pickupAddress!
            : 'Pickup';
        final drop =
            order.address.trim().isNotEmpty ? order.address : 'Drop-off';
        await PushNotificationService.instance.showIncomingRide(
          orderId: order.id,
          title: 'Incoming delivery job',
          body: '$pickup → $drop',
        );
      }
      return;
    }
    _activeOrderId = order.id;
    await WakelockPlus.enable();
    await IncomingRideRing.start();
    if (showNotification) {
      final pickup = order.pickupAddress?.trim().isNotEmpty == true
          ? order.pickupAddress!
          : 'Pickup';
      final drop = order.address.trim().isNotEmpty ? order.address : 'Drop-off';
      await PushNotificationService.instance.showIncomingRide(
        orderId: order.id,
        title: 'Incoming delivery job',
        body: '$pickup → $drop',
      );
    }
  }

  static Future<void> dismiss({String? orderId}) async {
    if (orderId != null &&
        _activeOrderId != null &&
        orderId != _activeOrderId) {
      return;
    }
    final id = orderId ?? _activeOrderId;
    _activeOrderId = null;
    IncomingRideRing.stop();
    await WakelockPlus.disable();
    if (id != null) {
      await PushNotificationService.instance.cancelIncomingRide(id);
    }
  }
}
