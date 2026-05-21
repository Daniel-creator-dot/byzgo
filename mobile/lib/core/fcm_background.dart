import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../firebase_options.dart';
import 'incoming_ride_notifications.dart';

/// FCM while app is backgrounded or screen is off — alarm notification + ringtone.
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
  final orderId = message.data['orderId']?.toString() ?? '';
  final title = message.notification?.title ??
      message.data['title']?.toString() ??
      (isRide ? 'Incoming delivery job' : 'BytzGo');
  final body = message.notification?.body ??
      message.data['body']?.toString() ??
      'Open BytzGo to accept';

  if (isRide) {
    try {
      await FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.bell,
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
    } catch (_) {}
  }

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(kIncomingRideChannel);
  await android?.createNotificationChannel(kTripChannel);

  final channelId = isRide ? incomingRideChannelId : kTripChannel.id;
  final notifId = isRide && orderId.isNotEmpty
      ? incomingRideNotificationId(orderId)
      : message.hashCode;

  await plugin.show(
    notifId,
    title,
    body,
    NotificationDetails(
      android: isRide
          ? incomingRideAndroidDetails()
          : AndroidNotificationDetails(
              kTripChannel.id,
              kTripChannel.name,
              channelDescription: kTripChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              visibility: NotificationVisibility.public,
            ),
    ),
  );
}
