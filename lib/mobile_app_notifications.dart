library mobile_app_notifications;

import 'dart:io';

import 'src/android_scheduler.dart' as android;
import 'src/ios_scheduler.dart' as ios;
import 'src/notification_plugin.dart' as plugin;

export 'src/adhan_player_channel.dart' show kAdhanStreamPrefKey;
export 'src/ring_alarm.dart' show ringAlarm;

/// Public entry point for scheduling and managing prayer-time notifications.
/// Implementation lives in [src] — this class is a thin delegating facade.
class ScheduleAdhan {
  ScheduleAdhan._();

  static final ScheduleAdhan instance = ScheduleAdhan._();

  Future<void> init() => plugin.init();

  Future<void> initAlarmManager() => android.initAlarmManager();

  Future<void> migrateOldAlarmIds() => android.migrateOldAlarmIds();

  Future<bool> checkIOSNotificationPermissions() =>
      ios.checkIOSNotificationPermissions();

  Future<void> scheduleAndroid() => android.scheduleAndroid();

  Future<void> schedule() async {
    if (Platform.isAndroid) {
      await android.scheduleAndroid();
    } else if (Platform.isIOS) {
      await ios.scheduleIOS();
    }
  }
}
