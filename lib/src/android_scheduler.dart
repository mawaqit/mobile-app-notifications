import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:intl/intl.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mobile_app_notifications/mobile_app_notifications.dart';
import 'package:mobile_app_notifications/models/notification/notification_info_model.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Module-level scheduling state (previously instance fields on ScheduleAdhan).
List<String> _newAlarmIds = [];
bool _isScheduling = false;

Future<void> initAlarmManager() async {
  await AndroidAlarmManager.initialize();
}

void _flushAlarmIdList() {
  _newAlarmIds = [];
}

/// Clear all alarms and reschedule - used for 500 error recovery.
///
/// Cancels every alarm we have a record of, clears tracking, and reschedules
/// from a clean state. This is near-unreachable in practice — scheduling caps
/// at ~10 alarms per cycle with deterministic IDs that replace rather than
/// accumulate — but kept as cheap insurance behind the 500 catch.
Future<void> _clearAllAndReschedule() async {
  Log.w('500 alarm limit hit - clearing all and rescheduling...');

  SharedPreferences prefs = await SharedPreferences.getInstance();

  // Cancel all tracked alarms
  List<String> alarms = prefs.getStringList('alarmIds') ?? [];
  for (String id in alarms) {
    try {
      await AndroidAlarmManager.cancel(int.parse(id));
    } catch (e) {
      // Ignore cancel errors
    }
  }

  // Clear tracked list
  await prefs.remove('alarmIds');
  _flushAlarmIdList();

  Log.i('Cleanup complete.');
}

Future<void> scheduleAndroid() async {
  if (_isScheduling) {
    Log.i("Scheduling in progress, please wait until it's completed...");
    return;
  }
  _isScheduling = true;
  // Outer try/finally guarantees _isScheduling resets even on unhandled
  // exceptions — without it, one stray throw permanently blocks every future
  // scheduleAndroid() call (early-return at the top), and the user receives
  // no further notifications until app restart.
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Fetch the new prayer list before touching existing alarms. If getPrayers()
    // throws (transient DB read failure, plugin error) we keep the old alarms
    // intact — an outdated schedule beats zero notifications until the next
    // schedule() call. An empty list, by contrast, is a deliberate state (user
    // removed their mosque) and must clear alarms so the adhan stops firing.
    List<NotificationInfoModel> prayersList;
    try {
      prayersList = await PrayerService().getPrayers();
    } catch (e, t) {
      Log.e(
        'Failed to fetch prayers during Android alarm scheduling; keeping existing alarms intact',
        error: e,
        stackTrace: t,
      );
      return;
    }

    List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];

    for (String alarmId in previousAlarms) {
      int id = int.parse(alarmId);
      await AndroidAlarmManager.cancel(id);
      Log.i('Cancelled Alarm Id: $id');
    }
    _flushAlarmIdList();
    await prefs.remove('alarmIds');
    await prefs.setStringList('alarmIds', []);

    for (var i = 0; i < prayersList.length; i++) {
      var prayer = prayersList[i];

      String minutesToAthan =
          await PrayersName().getStringText(prayer.notificationBeforeAthan);
      //Fetch App Language
      String appLanguage = await PrayersName().getLanguage();
      //Fetch App time format
      bool is24HourFormat = await PrayerTimeFormat().get24HoursFormatSetting();
      //for Pre notification
      var preNotificationTime = prayer.time!
          .subtract(Duration(minutes: prayer.notificationBeforeAthan));

      if (prayer.notificationBeforeAthan != 0 &&
          preNotificationTime.isAfter(DateTime.now())) {
        var id = (prayer.alarmId + 100000).toString();
        _newAlarmIds.add(id);
        try {
          await AndroidAlarmManager.oneShotAt(
              preNotificationTime, int.parse(id), ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'sound': 'mawaqit_id',
                'mosque': prayer.mosqueName,
                'prayer': prayer.prayerName,
                'time': prayer.notificationBeforeAthan.toString(),
                'isPreNotification': true,
                'minutesToAthan': minutesToAthan,
                'notificationBeforeShuruq': 0,
                'sound_type': prayer.soundType,
                'appLanguage': appLanguage,
                'is24HourFormat': is24HourFormat,
                'scheduledAtMillis':
                    preNotificationTime.millisecondsSinceEpoch,
                'prayerAtMillis': prayer.time!.millisecondsSinceEpoch,
              });
          Log.i(
              'Pre Notification scheduled for ${prayer.prayerName} at : $preNotificationTime Id: $id');
        } catch (e, t) {
          Log.e("Exception oneShotAt", error: e, stackTrace: t);
          // Auto-recover from 500 alarm limit. The explicit reset is required
          // here because the outer finally hasn't fired yet — without it, the
          // recursive scheduleAndroid() call would early-return.
          if (e.toString().contains('500')) {
            await _clearAllAndReschedule();
            _isScheduling = false;
            await scheduleAndroid();
            return;
          }
        }
      }
      //for Adhan notification
      String prayerTime = DateFormat('HH:mm').format(prayer.time!);
      DateTime notificationTime;
      int notificationBeforeShuruq;

      int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');
      if (index == 1) {
        notificationBeforeShuruq =
            prefs.getInt('notificationBeforeShuruq') ?? 0;

        notificationTime = prayer.time!
            .subtract(Duration(minutes: notificationBeforeShuruq));
      } else {
        notificationTime = prayer.time!;
        notificationBeforeShuruq = 0;
      }

      if (prayer.sound != 'SILENT' &&
          notificationTime.isAfter(DateTime.now())) {
        _newAlarmIds.add(prayer.alarmId.toString());
        try {
          await AndroidAlarmManager.oneShotAt(
              notificationTime, prayer.alarmId, ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'index': index,
                'sound': prayer.sound,
                'mosque': prayer.mosqueName,
                'prayer': prayer.prayerName,
                'time': prayerTime,
                'isPreNotification': false,
                'minutesToAthan': '',
                'notificationBeforeShuruq': notificationBeforeShuruq,
                'sound_type': prayer.soundType,
                'appLanguage': appLanguage,
                'is24HourFormat': is24HourFormat,
                'scheduledAtMillis': notificationTime.millisecondsSinceEpoch,
                'prayerAtMillis': prayer.time!.millisecondsSinceEpoch,
                'playInSilent': prayer.playInSilent,
                'customVolumeEnabled': prayer.customVolumeEnabled,
                'adhanVolume': prayer.adhanVolume,
              });
          Log.i(
              'Sound ${prayer.sound} Notification scheduled for ${prayer.prayerName} at : $notificationTime Id: ${prayer.alarmId}');
        } catch (e, t) {
          Log.e("Exception oneShotAt", error: e, stackTrace: t);
          // See note above on the explicit reset before recursion.
          if (e.toString().contains('500')) {
            await _clearAllAndReschedule();
            _isScheduling = false;
            await scheduleAndroid();
            return;
          }
        }
      }
    }
    await prefs.setStringList('alarmIds', _newAlarmIds);

    Log.i(_newAlarmIds.toList());
  } finally {
    _isScheduling = false;
  }
}
