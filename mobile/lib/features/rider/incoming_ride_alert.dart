import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/push_notification_service.dart';
import '../../models/order.dart';
import '../../shared/rider_trip.dart';
import 'incoming_ride_ring.dart';

/// Single entry for incoming-job audio: in-app ring OR notification sound, never both.
class IncomingRideAlert {
  IncomingRideAlert._();

  static String? _activeOrderId;

  static Future<void> raise(
    Order order, {
    /// True when app is backgrounded / screen off — use notification alarm only.
    bool useNotificationSound = false,
  }) async {
    if (!isOfferableOrder(order)) return;

    final pickup = order.pickupAddress?.trim().isNotEmpty == true
        ? order.pickupAddress!
        : 'Pickup';
    final drop =
        order.address.trim().isNotEmpty ? order.address : 'Drop-off';
    final title = 'Incoming delivery job';
    final body = '$pickup → $drop';

    if (_activeOrderId == order.id) {
      if (useNotificationSound) {
        await PushNotificationService.instance.showIncomingRide(
          orderId: order.id,
          title: title,
          body: body,
          playSound: true,
        );
      } else {
        await IncomingRideRing.start();
      }
      return;
    }

    _activeOrderId = order.id;
    await WakelockPlus.enable();

    if (useNotificationSound) {
      await IncomingRideRing.stop();
      await PushNotificationService.instance.showIncomingRide(
        orderId: order.id,
        title: title,
        body: body,
        playSound: true,
      );
    } else {
      await PushNotificationService.instance.cancelIncomingRide(order.id);
      await IncomingRideRing.start();
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
