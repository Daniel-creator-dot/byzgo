import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

/// Shows alerts when FCM arrives while the app is backgrounded or the screen is off.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  const tripChannel = AndroidNotificationChannel(
    'trip_updates',
    'Trip & chat alerts',
    description: 'Biker ETA, trip status, and chat messages',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  const rideChannel = AndroidNotificationChannel(
    'incoming_rides',
    'Incoming delivery jobs',
    description: 'Alerts when a new ride is offered — works when screen is off',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(tripChannel);
  await android?.createNotificationChannel(rideChannel);

  final title = message.notification?.title ?? 'BytzGo';
  final body = message.notification?.body ?? 'Open BytzGo to view';
  final type = message.data['type']?.toString() ?? '';
  final isRide = type == 'incoming-ride';
  final channelId = isRide ? 'incoming_rides' : 'trip_updates';

  await plugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        isRide ? rideChannel.name : tripChannel.name,
        channelDescription: isRide ? rideChannel.description : tripChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        visibility: NotificationVisibility.public,
        fullScreenIntent: isRide,
        category: isRide
            ? AndroidNotificationCategory.call
            : AndroidNotificationCategory.message,
        ticker: title,
      ),
    ),
  );
}
