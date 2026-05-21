import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/push_notification_service.dart';
import '../../models/order.dart';
import '../../shared/rider_trip.dart';
import 'incoming_ride_ring.dart';

/// Bolt-style incoming call: ring ~15s, then offer stays on screen until expiry.
class IncomingRideAlert {
  IncomingRideAlert._();

  /// How long the job "call" rings (Bolt-style).
  static const Duration callRingDuration = Duration(seconds: 15);

  static String? _activeOrderId;
  static Timer? _ringEndTimer;

  /// Seconds left in the call ring (15 → 0). UI can listen for countdown.
  static final ValueNotifier<int> ringSecondsLeft = ValueNotifier(0);

  static bool get isRinging => ringSecondsLeft.value > 0;

  static Future<void> raise(
    Order order, {
    /// True when app is backgrounded / screen off — use notification alarm only.
    bool useNotificationSound = false,
  }) async {
    if (!isOfferableOrder(order)) return;
    if (!PushNotificationService.instance.acceptsIncomingRideJobs) return;

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
        await IncomingRideRing.start(maxDuration: callRingDuration);
      }
      _scheduleRingEnd(order.id, cancelNotification: useNotificationSound);
      return;
    }

    _activeOrderId = order.id;
    await WakelockPlus.enable();

    if (useNotificationSound) {
      IncomingRideRing.stop();
      await PushNotificationService.instance.showIncomingRide(
        orderId: order.id,
        title: title,
        body: body,
        playSound: true,
      );
    } else {
      await PushNotificationService.instance.cancelIncomingRide(order.id);
      await IncomingRideRing.start(maxDuration: callRingDuration);
    }
    _scheduleRingEnd(order.id, cancelNotification: useNotificationSound);
  }

  static void _scheduleRingEnd(String orderId, {required bool cancelNotification}) {
    _ringEndTimer?.cancel();
    var left = callRingDuration.inSeconds;
    ringSecondsLeft.value = left;
    _ringEndTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      left--;
      if (left <= 0) {
        timer.cancel();
        _ringEndTimer = null;
        ringSecondsLeft.value = 0;
        IncomingRideRing.stop();
        if (cancelNotification) {
          unawaited(
            PushNotificationService.instance.cancelIncomingRide(orderId),
          );
        }
        return;
      }
      ringSecondsLeft.value = left;
    });
  }

  static void _cancelRingTimer() {
    _ringEndTimer?.cancel();
    _ringEndTimer = null;
    ringSecondsLeft.value = 0;
  }

  static Future<void> dismiss({String? orderId}) async {
    if (orderId != null &&
        _activeOrderId != null &&
        orderId != _activeOrderId) {
      return;
    }
    final id = orderId ?? _activeOrderId;
    _activeOrderId = null;
    _cancelRingTimer();
    IncomingRideRing.stop();
    await WakelockPlus.disable();
    if (id != null) {
      await PushNotificationService.instance.cancelIncomingRide(id);
    }
  }
}

void unawaited(Future<void> f) {}
