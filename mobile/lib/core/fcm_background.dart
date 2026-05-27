import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'incoming_ride_notifications.dart';
import 'push_session_context.dart';

/// FCM while app is backgrounded or screen is off — local notification on Android & iOS.
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
  final orderId = message.data['orderId']?.toString() ?? '';
  final title = message.notification?.title ??
      message.data['title']?.toString() ??
      (isRide ? 'Incoming delivery job' : 'BytzGo');
  final body = message.notification?.body ??
      message.data['body']?.toString() ??
      'Open BytzGo to accept';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await plugin.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
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
    platformTripNotificationDetails(
      android: isRide
          ? incomingRideAndroidDetails(playSound: true)
          : AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: isSupport ? Importance.high : Importance.max,
              priority: Priority.high,
              visibility: NotificationVisibility.public,
            ),
      incomingRide: isRide,
    ),
  );
}
