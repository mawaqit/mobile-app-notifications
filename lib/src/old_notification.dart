import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';

import '../helpers/device_ringtone_mode.dart';
import '../models/prayers/prayer_notification.dart';
import 'notification_plugin.dart';

/// Legacy 4.1.1 notification implementation.
/// Uses native NotificationManager via flutterLocalNotificationsPlugin with
/// the adhan sound configured on the notification channel.
Future<void> showOldNotification({
  required int id,
  required String prayer,
  required String title,
  required String mosque,
  required String sound,
  required SoundType soundType,
}) async {
  String? adhanSound;
  if (sound == 'DEFAULT') {
    adhanSound = null;
  } else if (soundType == SoundType.customSound) {
    adhanSound = sound.substring(0, sound.length - 4);
  } else {
    adhanSound = sound;
  }

  bool mute = await DeviceRingtoneMode.isMuted();
  Log.i('is mute: $mute');

  String baseChannelId = prayer.toLowerCase();
  String channelName = '$baseChannelId Adhan';
  String channelId = '$baseChannelId Adhan $sound';

  Log.t(" ----- ------- -- - - - --- -channelId: $channelId");
  final AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    mute ? 'Silent $channelId' : channelId,
    mute ? 'Silent' : channelName,
    channelDescription: 'Adhan notifications for $prayer',
    importance: Importance.max,
    priority: Priority.high,
    playSound: !mute,
    sound: (mute)
        ? const RawResourceAndroidNotificationSound('silent_sound')
        : soundType == SoundType.customSound
            ? RawResourceAndroidNotificationSound(adhanSound)
            : UriAndroidNotificationSound(adhanSound ?? ''),
    enableVibration: true,
    largeIcon: const DrawableResourceAndroidBitmap('logo'),
    icon: 'notification_icon',
    onlyAlertOnce: false,
    ticker: 'ticker',
    audioAttributesUsage: AudioAttributesUsage.alarm,
    visibility: NotificationVisibility.public,
    category: AndroidNotificationCategory.alarm,
  );

  final NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    mosque,
    platformChannelSpecifics,
  );
}
