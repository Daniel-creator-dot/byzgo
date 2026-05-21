import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'fcm_background.dart';
import 'incoming_ride_notifications.dart';
import 'session.dart';
import '../features/rider/incoming_ride_ring.dart';

/// Registers FCM and shows high-priority alerts when the app is backgrounded.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastToken;

  /// Rider shell listens to refresh offers when FCM arrives in foreground.
  void Function(Map<String, String> data)? onIncomingRidePush;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(kIncomingRideChannel);
    await android?.createNotificationChannel(kTripChannel);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
    }

    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint(
        'BytzGo push: Firebase not configured — add google-services.json or dart-defines',
      );
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromNotification);
    } catch (e, st) {
      debugPrint('BytzGo push init failed: $e\n$st');
    }
  }

  Future<void> ensureRegistered({
    required ApiClient api,
    required Session session,
  }) async {
    await initialize();
    if (!DefaultFirebaseOptions.isConfigured) return;
    if (!session.isAuthenticated) return;

    if (!kIsWeb) {
      final status = await Permission.notification.request();
      if (!status.isGranted && !status.isLimited) {
        debugPrint('BytzGo push: notification permission denied');
      }
    }

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
      );
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await messaging.setAutoInitEnabled(true);
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      if (token == _lastToken) return;
      _lastToken = token;
      await api.dio.post('/api/push/fcm-token', data: {
        'token': token,
        'platform': defaultTargetPlatform.name,
      });
      debugPrint('BytzGo push: FCM token registered');
    } catch (e) {
      debugPrint('BytzGo push: token registration failed: $e');
    }
  }

  /// High-priority incoming job (socket or background FCM).
  Future<void> showIncomingRide({
    required String orderId,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _local.show(
      incomingRideNotificationId(orderId),
      title,
      body,
      NotificationDetails(android: incomingRideAndroidDetails()),
      payload: jsonEncode({'type': 'incoming-ride', 'orderId': orderId}),
    );
  }

  Future<void> cancelIncomingRide(String orderId) async {
    await _local.cancel(incomingRideNotificationId(orderId));
  }

  /// In-app alert for trip/chat updates.
  Future<void> showTripAlert({
    required String title,
    required String body,
    String type = 'trip-update',
    String? orderId,
    bool highPriority = true,
  }) async {
    await initialize();
    if (type == 'incoming-ride' && orderId != null) {
      await showIncomingRide(orderId: orderId, title: title, body: body);
      await IncomingRideRing.start();
      return;
    }
    if (!kIsWeb) {
      try {
        await FlutterRingtonePlayer().playNotification();
      } catch (_) {}
    }
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kTripChannel.id,
          kTripChannel.name,
          channelDescription: kTripChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          category: highPriority
              ? AndroidNotificationCategory.message
              : AndroidNotificationCategory.status,
        ),
      ),
      payload: jsonEncode({'type': type, 'orderId': orderId ?? ''}),
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString() ?? '';
    if (type == 'incoming-ride') {
      unawaited(IncomingRideRing.start());
      final orderId = data['orderId']?.toString() ?? '';
      final title =
          message.notification?.title ?? data['title']?.toString() ?? 'Incoming delivery job';
      final body = message.notification?.body ??
          data['body']?.toString() ??
          'Open BytzGo to accept';
      if (orderId.isNotEmpty) {
        unawaited(showIncomingRide(orderId: orderId, title: title, body: body));
      } else {
        unawaited(_showLocal(message, type: type));
      }
      onIncomingRidePush?.call({
        for (final e in data.entries) e.key: e.value?.toString() ?? '',
      });
      return;
    }
    if (type == 'trip-message') {
      try {
        FlutterRingtonePlayer().playNotification();
      } catch (_) {}
    }
    unawaited(_showLocal(message, type: type));
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    final type = message.data['type']?.toString() ?? '';
    if (type == 'incoming-ride') {
      onIncomingRidePush?.call({
        for (final e in message.data.entries)
          e.key: e.value?.toString() ?? '',
      });
    }
    debugPrint('BytzGo push opened: ${message.data}');
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final type = data['type']?.toString() ?? '';
      if (type == 'incoming-ride') {
        onIncomingRidePush?.call({
          for (final e in data.entries) e.key: e.value?.toString() ?? '',
        });
      }
      debugPrint('BytzGo notification tap: $data');
    } catch (_) {}
  }

  Future<void> _showLocal(RemoteMessage message, {required String type}) async {
    final title = message.notification?.title ?? 'BytzGo';
    final body = message.notification?.body ?? 'New update';
    final isRide = type == 'incoming-ride';
    final orderId = message.data['orderId']?.toString() ?? '';

    if (isRide && orderId.isNotEmpty) {
      await showIncomingRide(orderId: orderId, title: title, body: body);
      return;
    }

    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kTripChannel.id,
          kTripChannel.name,
          channelDescription: kTripChannel.description,
          importance: Importance.max,
          priority: isRide ? Priority.max : Priority.high,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
