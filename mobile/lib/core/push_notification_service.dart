import 'dart:async' show StreamSubscription, unawaited;
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import '../models/auth_user.dart';
import '../models/role.dart';
import 'api_client.dart';
import 'fcm_background.dart';
import '../features/rider/incoming_ride_ring.dart';
import 'incoming_ride_notifications.dart';
import 'session.dart';

/// Registers FCM and shows high-priority alerts when the app is backgrounded.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastToken;
  AppRole? _activeRole;
  ApiClient? _boundApi;
  Session? _boundSession;
  StreamSubscription<String>? _tokenRefreshSub;

  bool get acceptsIncomingRideJobs => _activeRole == AppRole.rider;

  /// Rider shell listens to refresh offers when FCM arrives in foreground.
  void Function(Map<String, String> data)? onIncomingRidePush;

  static String pushPlatformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        return defaultTargetPlatform.name.toLowerCase();
    }
  }

  /// Call after login, restore, or logout so incoming-job alerts respect account role.
  Future<void> syncActiveRole({
    required ApiClient api,
    required AuthUser? user,
    required Session session,
  }) async {
    _boundApi = api;
    _boundSession = session;
    _activeRole = user?.role;
    if (!acceptsIncomingRideJobs) {
      onIncomingRidePush = null;
    }
    if (!session.isAuthenticated) {
      _activeRole = null;
      _lastToken = null;
      onIncomingRidePush = null;
      return;
    }
    await ensureRegistered(api: api, session: session);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(kIncomingRideChannel);
    await android?.createNotificationChannel(kTripChannel);
    await android?.createNotificationChannel(kSupportChannel);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      final ios = _local.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
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
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => unawaited(_registerToken(token, force: true)),
      );
    } catch (e, st) {
      debugPrint('BytzGo push init failed: $e\n$st');
    }
  }

  /// Rider opened app from a killed state via notification tap.
  Future<void> handleColdStartNotification() async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        _onOpenedFromNotification(message);
      }
    } catch (e) {
      debugPrint('BytzGo push: getInitialMessage failed: $e');
    }
  }

  Future<void> ensureRegistered({
    required ApiClient api,
    required Session session,
  }) async {
    await initialize();
    if (!DefaultFirebaseOptions.isConfigured) return;
    if (!session.isAuthenticated) return;

    _boundApi = api;
    _boundSession = session;

    if (!kIsWeb) {
      final status = await Permission.notification.request();
      if (!status.isGranted && !status.isLimited) {
        debugPrint('BytzGo push: notification permission denied');
      }
    }

    try {
      final messaging = FirebaseMessaging.instance;
      // Foreground: rider shell shows in-app ring; suppress duplicate FCM banner.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
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
      await _registerToken(token, force: true);
    } catch (e) {
      debugPrint('BytzGo push: token registration failed: $e');
    }
  }

  Future<void> _registerToken(String token, {bool force = false}) async {
    final api = _boundApi;
    final session = _boundSession;
    if (api == null || session == null || !session.isAuthenticated) return;
    if (!force && token == _lastToken) {
      // Still refresh server row so platform/user_id stay current after reinstall.
      try {
        await api.dio.post('/api/push/fcm-token', data: {
          'token': token,
          'platform': pushPlatformLabel(),
        });
      } catch (_) {}
      return;
    }
    _lastToken = token;
    await api.dio.post('/api/push/fcm-token', data: {
      'token': token,
      'platform': pushPlatformLabel(),
    });
    debugPrint('BytzGo push: FCM token registered (${pushPlatformLabel()})');
  }

  /// High-priority incoming job (socket or background FCM).
  Future<void> showIncomingRide({
    required String orderId,
    required String title,
    required String body,
    bool playSound = false,
  }) async {
    if (!acceptsIncomingRideJobs) return;
    await initialize();
    await _local.show(
      incomingRideNotificationId(orderId),
      title,
      body,
      incomingRideNotificationDetails(playSound: playSound),
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
      if (acceptsIncomingRideJobs) {
        await showIncomingRide(
          orderId: orderId,
          title: title,
          body: body,
          playSound: false,
        );
      }
      return;
    }
    if (!kIsWeb) {
      try {
        await FlutterRingtonePlayer().playNotification();
      } catch (_) {}
    }
    final isSupport = type == 'support-message';
    final channel = isSupport ? kSupportChannel : kTripChannel;
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: isSupport ? Importance.high : Importance.max,
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
      if (!acceptsIncomingRideJobs) return;
      final payload = {
        for (final e in data.entries) e.key: e.value?.toString() ?? '',
      };
      unawaited(IncomingRideRing.start());
      onIncomingRidePush?.call(payload);
      final orderId = data['orderId']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        unawaited(showIncomingRide(
          orderId: orderId,
          title: data['title']?.toString() ??
              message.notification?.title ??
              'New delivery job',
          body: data['body']?.toString() ??
              message.notification?.body ??
              'Open BytzGo to accept',
          playSound: false,
        ));
      }
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
      if (!acceptsIncomingRideJobs) return;
      unawaited(IncomingRideRing.start());
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
      if (type == 'incoming-ride' && acceptsIncomingRideJobs) {
        unawaited(IncomingRideRing.start());
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
      if (acceptsIncomingRideJobs) {
        await showIncomingRide(
          orderId: orderId,
          title: title,
          body: body,
          playSound: true,
        );
      }
      return;
    }

    final isSupport = type == 'support-message';
    final channel = isSupport ? kSupportChannel : kTripChannel;
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: isSupport ? Importance.high : Importance.max,
          priority: isRide ? Priority.max : Priority.high,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
