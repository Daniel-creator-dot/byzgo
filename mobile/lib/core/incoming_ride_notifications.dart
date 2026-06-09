import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android channel for loud incoming-job alerts (screen off / DND bypass where allowed).
const String incomingRideChannelId = 'incoming_rides_alarm';

const AndroidNotificationChannel kIncomingRideChannel = AndroidNotificationChannel(
  incomingRideChannelId,
  'Incoming delivery jobs',
  description: 'Ringing alerts for new delivery offers — works when screen is off',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

const AndroidNotificationChannel kTripChannel = AndroidNotificationChannel(
  'trip_updates',
  'Trip & chat alerts',
  description: 'Biker ETA, trip status, and chat messages',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const AndroidNotificationChannel kSupportChannel = AndroidNotificationChannel(
  'support_updates',
  'Support messages',
  description: 'Replies from BytzGo support on your tickets',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

int incomingRideNotificationId(String orderId) =>
    orderId.hashCode & 0x7fffffff;

const DarwinNotificationDetails _darwinIncomingRide = DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true,
  presentSound: true,
  interruptionLevel: InterruptionLevel.timeSensitive,
);

const DarwinNotificationDetails _darwinTripAlert = DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true,
  presentSound: true,
);

NotificationDetails platformTripNotificationDetails({
  required AndroidNotificationDetails android,
  bool incomingRide = false,
}) {
  return NotificationDetails(
    android: android,
    iOS: incomingRide ? _darwinIncomingRide : _darwinTripAlert,
  );
}

NotificationDetails incomingRideNotificationDetails({
  bool fullScreen = true,
  bool ongoing = true,
  /// When the in-app [IncomingRideRing] is playing, keep this false to avoid double audio.
  bool playSound = false,
}) {
  return NotificationDetails(
    android: incomingRideAndroidDetails(
      fullScreen: fullScreen,
      ongoing: ongoing,
      playSound: playSound,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      interruptionLevel: InterruptionLevel.timeSensitive,
      threadIdentifier: 'incoming_rides_alarm',
    ),
  );
}

AndroidNotificationDetails incomingRideAndroidDetails({
  bool fullScreen = true,
  bool ongoing = true,
  /// When the in-app [IncomingRideRing] is playing, keep this false to avoid double audio.
  bool playSound = false,
}) {
  return AndroidNotificationDetails(
    incomingRideChannelId,
    kIncomingRideChannel.name,
    channelDescription: kIncomingRideChannel.description,
    importance: Importance.max,
    priority: Priority.max,
    visibility: NotificationVisibility.public,
    fullScreenIntent: fullScreen,
    ongoing: ongoing,
    autoCancel: false,
    category: AndroidNotificationCategory.call,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    playSound: playSound,
    enableVibration: true,
    ticker: 'Incoming delivery job',
  );
}
