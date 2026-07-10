import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'pending_incoming_ride_action_store.dart';
import 'pending_incoming_ride_store.dart';

typedef IncomingRideCallAction = void Function(
  String action,
  Map<String, String> data,
);

/// Native incoming-call UI (CallKit on iOS, full-screen on Android) for delivery offers.
class IncomingRideCallKit {
  IncomingRideCallKit._();

  static const _offerDurationMs = 30000;
  static bool _initialized = false;
  static StreamSubscription<CallEvent?>? _eventSub;
  static IncomingRideCallAction? onRideAction;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _eventSub = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);
    } catch (e, st) {
      debugPrint('BytzGo CallKit onEvent failed: $e\n$st');
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      } catch (e) {
        debugPrint('BytzGo CallKit full-intent permission failed: $e');
      }
    }

    // Register background handlers after first frame — forced registration at
    // cold start can crash release iOS before Flutter paints.
    unawaited(_registerBackgroundHandlers());
  }

  static Future<void> _registerBackgroundHandlers() async {
    try {
      await FlutterCallkitIncoming.onBackgroundMessage(
        incomingRideCallkitBackgroundHandler,
      );
    } catch (e, st) {
      debugPrint('BytzGo CallKit onBackgroundMessage skipped: $e\n$st');
    }
    try {
      FlutterCallkitIncoming.acceptCallHandle(incomingRideAcceptCallHandle);
    } catch (e, st) {
      debugPrint('BytzGo CallKit acceptCallHandle skipped: $e\n$st');
    }
  }

  static Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    onRideAction = null;
  }

  static Map<String, String> _normalizeExtra(Map<dynamic, dynamic> raw) {
    return {
      for (final e in raw.entries) e.key.toString(): e.value?.toString() ?? '',
    };
  }

  static Map<String, String> _paramsToPayload(CallKitParams params) {
    final extra = params.extra ?? {};
    final payload = _normalizeExtra(extra);
    if (payload['orderId']?.isNotEmpty != true) {
      payload['orderId'] = params.id;
    }
    if (payload['type']?.isNotEmpty != true) {
      payload['type'] = 'incoming-ride';
    }
    return payload;
  }

  static Future<void> showIncomingRide(Map<String, String> data) async {
    await initialize();
    final orderId = data['orderId']?.trim() ?? '';
    if (orderId.isEmpty) return;
    if (PendingIncomingRideStore.isExpired(data)) return;

    final pickup = data['pickup']?.trim().isNotEmpty == true
        ? data['pickup']!.trim()
        : 'Pickup';
    final drop = data['address']?.trim().isNotEmpty == true
        ? data['address']!.trim()
        : 'Drop-off';

    final extra = <String, dynamic>{
      ...data,
      'type': 'incoming-ride',
      'orderId': orderId,
    };

    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: orderId,
        nameCaller: 'Incoming delivery job',
        appName: 'BytzGo',
        handle: '$pickup → $drop',
        type: 0,
        duration: _offerDurationMs,
        extra: extra,
        missedCallNotification: const NotificationParams(
          showNotification: false,
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowFullLockedScreen: true,
          isShowLogo: false,
          isShowCallID: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          actionColor: '#84CC16',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming delivery jobs',
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: false,
          ringtonePath: 'system_ringtone_default',
          includesCallsInRecents: false,
        ),
      ),
    );
  }

  static Future<void> endCall(String orderId) async {
    if (orderId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(orderId);
    } catch (e) {
      debugPrint('BytzGo CallKit endCall failed: $e');
    }
  }

  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('BytzGo CallKit endAllCalls failed: $e');
    }
  }

  static Future<void> handleBackgroundEvent(CallEvent event) async {
    if (event is CallEventActionCallAccept) {
      await _persistCallAction('accept', _paramsToPayload(event.callKitParams));
    } else if (event is CallEventActionCallDecline) {
      await _persistCallAction('decline', _paramsToPayload(event.callKitParams));
    } else if (event is CallEventActionCallTimeout) {
      await _persistCallAction('timeout', {
        'type': 'incoming-ride',
        'orderId': event.id,
      });
    }
  }

  static Future<void> handleAcceptFromNative(Map<dynamic, dynamic> data) async {
    await _persistCallAction('accept', _normalizeExtra(data));
  }

  static Future<void> _persistCallAction(
    String action,
    Map<String, String> data,
  ) async {
    if (data['orderId']?.isEmpty ?? true) return;
    await PendingIncomingRideStore.save(data);
    await PendingIncomingRideActionStore.save(action, data);
    onRideAction?.call(action, data);
  }

  static void _onCallEvent(CallEvent? event) {
    if (event == null) return;
    if (event is CallEventActionCallAccept) {
      unawaited(_persistCallAction('accept', _paramsToPayload(event.callKitParams)));
    } else if (event is CallEventActionCallDecline) {
      unawaited(_persistCallAction('decline', _paramsToPayload(event.callKitParams)));
    } else if (event is CallEventActionCallTimeout) {
      unawaited(_persistCallAction('timeout', {
        'type': 'incoming-ride',
        'orderId': event.id,
      }));
    }
  }
}

@pragma('vm:entry-point')
Future<void> incomingRideCallkitBackgroundHandler(CallEvent event) async {
  WidgetsFlutterBinding.ensureInitialized();
  await IncomingRideCallKit.handleBackgroundEvent(event);
}

@pragma('vm:entry-point')
void incomingRideAcceptCallHandle(Map<dynamic, dynamic> data) {
  unawaited(IncomingRideCallKit.handleAcceptFromNative(data));
}
