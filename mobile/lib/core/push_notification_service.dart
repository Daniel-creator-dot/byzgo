import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'fcm_background.dart';
import 'session.dart';

/// Registers FCM and shows high-priority alerts when the app is backgrounded.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    const channel = AndroidNotificationChannel(
      'incoming_rides',
      'Incoming delivery jobs',
      description: 'Alerts when a new ride is offered',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint('BytzGo push: Firebase not configured — add google-services.json or dart-defines');
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
      await messaging.requestPermission(alert: true, badge: true, sound: true);
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

  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'incoming-ride') {
      FlutterRingtonePlayer().playNotification();
    }
    _showLocal(message);
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    debugPrint('BytzGo push opened: ${message.data}');
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      debugPrint('BytzGo notification tap: $data');
    } catch (_) {}
  }

  Future<void> _showLocal(RemoteMessage message) async {
    final title = message.notification?.title ?? 'BytzGo';
    final body = message.notification?.body ?? 'New update';
    final data = message.data;

    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'incoming_rides',
          'Incoming delivery jobs',
          channelDescription: 'Alerts when a new ride is offered',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
