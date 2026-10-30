import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

import 'full_adhan_ios_channel.dart';
import 'notification_plugin.dart';

Future<bool> checkIOSNotificationPermissions() async {
  final iosPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
  final permissionStatus = await iosPlugin?.checkPermissions();
  if (permissionStatus == null) {
    Log.i('Could not get permission status');
    return false;
  } else {
    Log.i('OverAll: ${permissionStatus.isEnabled}');
    Log.i('Alert: ${permissionStatus.isAlertEnabled}');
    Log.i('Badge: ${permissionStatus.isBadgeEnabled}');
    Log.i('Sound: ${permissionStatus.isSoundEnabled}');
    return permissionStatus.isEnabled &&
        permissionStatus.isAlertEnabled &&
        permissionStatus.isBadgeEnabled &&
        permissionStatus.isSoundEnabled;
  }
}

/// Whether this device can play the full adhan through AlarmKit (iOS 26+).
Future<bool> supportsFullAdhanIOS() async {
  try {
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    return isFullAdhanSupportedVersion(iosInfo.systemVersion);
  } catch (e, s) {
    Log.e('Could not read iOS version; full adhan disabled', error: e, stackTrace: s);
    return false;
  }
}

@visibleForTesting
bool isFullAdhanSupportedVersion(String systemVersion) {
  final major = int.tryParse(systemVersion.split('.').first.trim()) ?? 0;
  return major >= 26;
}

Future<void> scheduleIOS() async {
  try {
    // Clear all scheduled notifications (UN path + native AlarmKit path)
    await flutterLocalNotificationsPlugin.cancelAll();
    await FullAdhanIOSChannel.cancelAll();
    Log.i('Cleared previous Notifications');

    // Retrieve SharedPreferences and prayers list
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var prayersList = await PrayerService().getPrayers();
    int i = 0, j = 0;

    // Payloads for prayers that should be played by the native AlarmKit-based
    // implementation instead of the UN notification path (full adhan).
    final List<Map<String, dynamic>> fullAdhanPayloads = [];
    // Below iOS 26 the native side rejects AlarmKit alarms, so a full-adhan
    // prayer would get no notification at all; keep it on the UN path instead.
    final bool fullAdhanSupported = await supportsFullAdhanIOS();

    if (prayersList.isEmpty) {
      return; // Exit early if there are no prayers
    } else {
      // Loop to schedule up to 63 notifications
      while (i < prayersList.length && j < 63) {
        var prayer = prayersList[i];
        int index =
            await PrayersName().getPrayerIndex(prayer.prayerName ?? '');

        // Fetch prayer translations and preset strings
        String translatedPrayerName = prayer.prayerName ?? 'Unknown';
        String minutesToAthan =
            await PrayersName().getStringText(prayer.notificationBeforeAthan);
        String inText = await PrayersName().getInText();

        // Pre-notification logic
        var preNotificationTime = prayer.time!
            .subtract(Duration(minutes: prayer.notificationBeforeAthan));

        /// PRE NOTIFICATION
        if (index != 1 &&
            prayer.notificationBeforeAthan != 0 &&
            preNotificationTime.isAfter(DateTime.now()) &&
            prayer.hasPreAdhan) {
          // Fajr adhan reminder: titled and played like the Shuruq one.
          String minutes =
              await PrayersName().getMinutesText(prayer.notificationBeforeAthan);
          String title =
              '$translatedPrayerName $inText ${prayer.notificationBeforeAthan} $minutes';
          if (prayer.preUseFullAdhanIOS && fullAdhanSupported) {
            fullAdhanPayloads.add({
              'alarmId': prayer.alarmId + 100000,
              'fireDateMillis': preNotificationTime.millisecondsSinceEpoch,
              'prayerIndex': index,
              'title': title,
              'body': prayer.mosqueName,
              'soundAssetId': prayer.preSound,
              'soundType': prayer.preSoundType,
            });
            Log.i(
                'Full adhan pre notification queued for native for ${prayer.prayerName} at: $preNotificationTime Id: ${prayer.alarmId + 100000}');
          } else {
            String? soundFile;
            if (prayer.preSoundType == SoundType.systemSound.name) {
              soundFile = await PrayerService().getDeviceSound(prayer.preSound);
            }
            await iosNotificationSchedular(
              prayer.alarmId + 100000,
              preNotificationTime,
              title,
              prayer.mosqueName,
              soundFile ?? prayer.preSound,
            );
            Log.i(
                'Adhan pre notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: ${prayer.alarmId + 100000}');
            j++;
          }
        } else if (index != 1 &&
            prayer.notificationBeforeAthan != 0 &&
            preNotificationTime.isAfter(DateTime.now())) {
          String title =
              '${prayer.notificationBeforeAthan} $minutesToAthan $translatedPrayerName';
          await iosNotificationSchedular(
            prayer.alarmId + 100000,
            preNotificationTime,
            title,
            prayer.mosqueName,
            null,
          );
          Log.i(
              'Pre Notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: ${prayer.alarmId + 100000}');
          j++;
        }

        // Main Athan notification logic
        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        DateTime notificationTime = prayer.time!;
        //Fetch App Language
        String languageCode = await PrayersName().getLanguage();
        //Fetch App time format
        bool is24HourFormat =
            await PrayerTimeFormat().get24HoursFormatSetting();
        // Make notification time on the base of TIME FORMAT and SELECTED LANGUAGE from APP
        String formatedPrayerTime = PrayerTimeFormat().getFormattedPrayerTime(
            prayerTime: prayerTime,
            timeFormat: is24HourFormat,
            selectedLanguage: languageCode);
        String notificationTitle =
            '$translatedPrayerName $formatedPrayerTime';
        int notificationBeforeShuruq;

        // Handle Shuruq timing if the prayer is Fajr (index == 1)
        if (index == 1) {
          // The lead time lives on the Shuruq record; the legacy prefs key wins
          // while it exists (app builds that predate the move, or before the app
          // has started once to migrate it).
          notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ??
              prayer.notificationBeforeAthan;
          notificationTime = prayer.time!
              .subtract(Duration(minutes: notificationBeforeShuruq));
          String minutes =
              await PrayersName().getMinutesText(notificationBeforeShuruq);
          notificationTitle =
              '$translatedPrayerName $inText $notificationBeforeShuruq $minutes';
        }

        if (prayer.sound != 'SILENT' &&
            notificationTime.isAfter(DateTime.now())) {
          // Hand off to native AlarmKit path when enabled — the UN sound is
          // capped at ~30s, so the full adhan can't play through it.
          if (prayer.useFullAdhanIOS && fullAdhanSupported) {
            fullAdhanPayloads.add({
              'alarmId': prayer.alarmId,
              'fireDateMillis': notificationTime.millisecondsSinceEpoch,
              'prayerIndex': index,
              'title': notificationTitle,
              'body': prayer.mosqueName,
              'soundAssetId': prayer.sound,
              'soundType': prayer.soundType,
            });
            Log.i(
                'Full adhan queued for native for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
          } else if (prayer.soundType == SoundType.systemSound.name) {
            String? soundFile;

            if (prayer.sound?.isNotEmpty == true) {
              soundFile =
                  await PrayerService().getDeviceSound(prayer.sound ?? "");
            }

            await iosNotificationSchedular(
              prayer.alarmId,
              notificationTime,
              notificationTitle,
              prayer.mosqueName,
              soundFile ?? prayer.sound,
            );
            Log.i(
                'Notification scheduled for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
            j++;
          } else {
            await iosNotificationSchedular(
              prayer.alarmId,
              notificationTime,
              notificationTitle,
              prayer.mosqueName,
              prayer.sound,
            );
            Log.i(
                'Notification scheduled for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
            j++;
          }
        }

        // Move to the next prayer
        i++;
      }
    }
    // Hand off full-adhan prayers to the native AlarmKit-based scheduler.
    // Done after the UN loop so a single channel call carries all prayers.
    if (fullAdhanPayloads.isNotEmpty) {
      await FullAdhanIOSChannel.schedule(fullAdhanPayloads);
      Log.i('Full adhan handoff: ${fullAdhanPayloads.length} prayer(s)');
    }
  } catch (e, s) {
    Log.e('Error in scheduleIOS: $e', error: e, stackTrace: s);
  }
  final pending =
      await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  Log.i('iOS pending notifications count: ${pending.length}');
}

Future<void> iosNotificationSchedular(int? id, DateTime date, String? title,
    String? body, String? soundId) async {
  try {
    final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
        sound: soundId == 'DEFAULT' ? null : soundId,
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.critical);

    final platformChannelSpecifics = NotificationDetails(
      iOS: iOSPlatformChannelSpecifics,
    );

    tzl.initializeTimeZones();
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(timeZoneName);
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    final scheduledDate = tz.TZDateTime.from(date, location);

    tz.TZDateTime now = tz.TZDateTime.now(location);
    if (now.isAfter(scheduledDate)) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id!,
      title,
      body,
      scheduledDate,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: 'scheudle date: $scheduledDate , sound id: $soundId',
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
    );
  } catch (e, s) {
    Log.e("Exception iosNotificationSchedular", error: e, stackTrace: s);
  }
}
