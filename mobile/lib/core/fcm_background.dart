import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'incoming_ride_notifications.dart';
import 'pending_incoming_ride_store.dart';
import 'push_session_context.dart';

/// FCM while app is backgrounded or screen is off — one alarm notification (no in-app ring).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  final type = message.data['type']?.toString() ?? '';
  final isRide = type == 'incoming-ride';
  if (isRide && !await PushSessionContext.isRider()) {
    return;
  }

  final payload = {
    for (final e in message.data.entries) e.key: e.value?.toString() ?? '',
  };
  if (isRide) {
    await PendingIncomingRideStore.save(payload);
  }

  // iOS: lock-screen alert+sound comes from APNs — skip duplicate local banner.
  if (isRide &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      message.notification != null) {
    return;
  }
  final orderId = message.data['orderId']?.toString() ?? '';
  final title = message.notification?.title ??
      message.data['title']?.toString() ??
      (isRide ? 'Incoming delivery job' : 'BytzGo');
  final body = message.notification?.body ??
      message.data['body']?.toString() ??
      'Open BytzGo to accept';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await plugin.initialize(
    const InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    ),
  );

  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final ios = plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  await ios?.requestPermissions(alert: true, badge: true, sound: true);
  await android?.createNotificationChannel(kIncomingRideChannel);
  await android?.createNotificationChannel(kTripChannel);
  await android?.createNotificationChannel(kSupportChannel);

  final notifId = isRide && orderId.isNotEmpty
      ? incomingRideNotificationId(orderId)
      : message.hashCode;

  final isSupport = type == 'support-message';
  final channel = isSupport ? kSupportChannel : kTripChannel;
  await plugin.show(
    notifId,
    title,
    body,
    isRide
        ? incomingRideNotificationDetails(playSound: true)
        : NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: isSupport ? Importance.high : Importance.max,
              priority: Priority.high,
              visibility: NotificationVisibility.public,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
    payload: isRide ? jsonEncode(payload) : null,
  );
}
