import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mobile_app_notifications/mobile_app_notifications.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';

import 'adhan_player_channel.dart';
import 'notification_plugin.dart';
import 'pre_notification.dart';

const Duration _staleAlarmGracePeriod = Duration(minutes: 10);

int? _readEpochMillis(Map<String, dynamic> data, String key) {
  final dynamic value = data[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

bool _isAlarmStillRelevant(Map<String, dynamic> data) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final scheduledAtMillis = _readEpochMillis(data, 'scheduledAtMillis');
  final prayerAtMillis = _readEpochMillis(data, 'prayerAtMillis');
  final isPreNotification = data['isPreNotification'] == true;

  // Backward compatibility for already-scheduled alarms that don't carry timestamps yet.
  if (scheduledAtMillis == null || prayerAtMillis == null) {
    return true;
  }

  if (isPreNotification) {
    return now >= scheduledAtMillis && now < prayerAtMillis;
  }

  return now >= scheduledAtMillis &&
      now <= prayerAtMillis + _staleAlarmGracePeriod.inMilliseconds;
}

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  if (!_isAlarmStillRelevant(data)) {
    Log.w('Skipping stale alarm $id');
    ScheduleAdhan.instance.schedule();
    return;
  }

  String sound = data['sound'];
  String mosque = data['mosque'];
  String prayer = data['prayer'];
  String time = data['time'];
  SoundType soundType =
      SoundType.values.firstWhere((e) => e.name == data['sound_type']);
  bool isPreNotification = data['isPreNotification'];
  String minutesToAthan = data['minutesToAthan'];
  int notificationBeforeShuruq = data['notificationBeforeShuruq'];
  String appLanguage = data['appLanguage'] ?? 'en';
  bool is24HourFormat = data['is24HourFormat'] ?? true;
  bool playInSilent = data['playInSilent'] ?? false;

  String notificationTitle;
  try {
    if (isPreNotification) {
      notificationTitle = '$time $minutesToAthan $prayer';
    } else if (notificationBeforeShuruq != 0) {
      String inText = await PrayersName().getInText();
      String minutes =
          await PrayersName().getMinutesText(notificationBeforeShuruq);
      notificationTitle = '$prayer $inText $notificationBeforeShuruq $minutes';
    } else {
      String formattedTime = PrayerTimeFormat().getFormattedPrayerTime(
          prayerTime: time,
          timeFormat: is24HourFormat,
          selectedLanguage: appLanguage);
      notificationTitle = '$prayer  $formattedTime';
    }

    if (isPreNotification) {
      await showPreNotification(id, prayer, notificationTitle, mosque);
    } else {
      // Fix A: clear the matching pre-notification (if still in the tray) before
      // the adhan service posts its own notification. Pre-notif ID = adhan ID + 100000.
      try {
        await flutterLocalNotificationsPlugin.cancel(id + 100000);
      } catch (_) {}
      await playAdhanNative(
        sound: sound,
        soundType: soundType,
        title: notificationTitle,
        body: mosque,
        playInSilent: playInSilent,
      );
    }

    ScheduleAdhan scheduleAdhan = ScheduleAdhan.instance;
    scheduleAdhan.schedule();
  } catch (e, t) {
    Log.e("Exception ringAlarm", error: e, stackTrace: t);
  }
}
