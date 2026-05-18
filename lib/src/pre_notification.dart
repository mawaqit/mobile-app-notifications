import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile_app_notifications/helpers/device_ringtone_mode.dart';

import 'notification_plugin.dart';

/// Pre-notification (heads-up before adhan). Stays on the notification path —
/// it's short, doesn't play the adhan, and respects ringer mute.
Future<void> showPreNotification(
    int id, String prayer, String title, String body) async {
  final bool mute = await DeviceRingtoneMode.isMuted();
  final String baseChannelId = prayer.toLowerCase();
  final String channelId = 'Pre $baseChannelId ';

  final androidDetails = AndroidNotificationDetails(
    mute ? 'Silent $channelId' : channelId,
    mute ? 'Silent' : channelId,
    channelDescription: 'Pre Adhan notifications for $prayer',
    importance: Importance.max,
    priority: Priority.high,
    playSound: !mute,
    sound:
        mute ? const RawResourceAndroidNotificationSound('silent_sound') : null,
    enableVibration: true,
    largeIcon: const DrawableResourceAndroidBitmap('logo'),
    icon: 'notification_icon',
    onlyAlertOnce: false,
    ticker: 'ticker',
    audioAttributesUsage: AudioAttributesUsage.alarm,
    visibility: NotificationVisibility.public,
    category: AndroidNotificationCategory.alarm,
  );

  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}
