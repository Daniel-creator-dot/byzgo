import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  final title = message.notification?.title ?? 'New delivery job';
  final body = message.notification?.body ?? 'Open BytzGo to view';

  await plugin.show(
    message.hashCode,
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
        visibility: NotificationVisibility.public,
      ),
    ),
  );
}
