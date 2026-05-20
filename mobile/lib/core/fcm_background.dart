import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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
    description: 'Alerts when a new ride is offered',
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
  final channelId =
      type == 'incoming-ride' ? 'incoming_rides' : 'trip_updates';

  await plugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'incoming_rides' ? rideChannel.name : tripChannel.name,
        importance: Importance.max,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
      ),
    ),
  );
}
