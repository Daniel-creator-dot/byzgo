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

int incomingRideNotificationId(String orderId) =>
    orderId.hashCode & 0x7fffffff;

AndroidNotificationDetails incomingRideAndroidDetails({
  bool fullScreen = true,
  bool ongoing = true,
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
    playSound: true,
    enableVibration: true,
    ticker: 'Incoming delivery job',
  );
}
