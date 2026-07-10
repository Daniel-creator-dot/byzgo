import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/incoming_ride_callkit.dart';
import '../../core/push_notification_service.dart';
import '../../core/pending_incoming_ride_store.dart';
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
    /// True when app is backgrounded / screen off — use CallKit full-screen UI.
    bool useCallKit = false,
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

    final payload = <String, String>{
      'type': 'incoming-ride',
      'orderId': order.id,
      'title': title,
      'body': body,
      'pickup': pickup,
      'address': drop,
      'status': order.status,
      'orderType': order.orderType ?? 'courier',
      if (order.expiresAt != null) 'expiresAt': order.expiresAt!,
    };

    if (_activeOrderId == order.id) {
      if (useCallKit) {
        unawaited(IncomingRideCallKit.showIncomingRide(payload));
      } else {
        unawaited(IncomingRideRing.start(maxDuration: callRingDuration));
      }
      _scheduleRingEnd(order.id, endCallKit: useCallKit);
      return;
    }

    _activeOrderId = order.id;

    if (useCallKit) {
      IncomingRideRing.stop();
      unawaited(IncomingRideCallKit.showIncomingRide(payload));
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(IncomingRideRing.start(maxDuration: callRingDuration));
      unawaited(WakelockPlus.enable());
      unawaited(PushNotificationService.instance.cancelIncomingRide(order.id));
    }
    _scheduleRingEnd(order.id, endCallKit: useCallKit);
  }

  static void _scheduleRingEnd(String orderId, {required bool endCallKit}) {
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
        if (endCallKit) {
          unawaited(IncomingRideCallKit.endCall(orderId));
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
      await IncomingRideCallKit.endCall(id);
      await PushNotificationService.instance.cancelIncomingRide(id);
    }
    await PendingIncomingRideStore.clear();
  }
}

