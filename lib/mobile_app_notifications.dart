// ignore_for_file: avoid_print, unused_local_variable

library mobile_app_notifications;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app_notifications/helpers/alarm_manager_helper.dart';
import 'package:mobile_app_notifications/helpers/device_ringtone_mode.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  print('from ringAlarm');

  // Check if notification is stale (time was manually changed forward)
  String? scheduledTime = data['scheduledTime'];
  if (!NotificationFreshnessChecker.isFresh(scheduledTime)) {
    await ScheduleThrottleHelper.removeFiredAlarm(id);
    return; // Skip stale notification
  }

  String sound = data['sound'];
  String mosque = data['mosque'];
  String prayer = data['prayer'];
  String time = data['time'];
  SoundType soundType = SoundType.values.firstWhere((e) => e.name == data['sound_type']);
  bool isPreNotification = data['isPreNotification'];
  String minutesToAthan = data['minutesToAthan'];
  int notificationBeforeShuruq = data['notificationBeforeShuruq'];
  String appLanguage = data['appLanguage'] ?? 'en';
  bool is24HourFormat = data['is24HourFormat'] ?? true;

  String? adhanSound;
  String notificationTitle;
  try {
    if (isPreNotification) {
      notificationTitle = '$time $minutesToAthan $prayer';
    } else {
      if (notificationBeforeShuruq != 0) {
        String inText = await PrayersName().getInText();
        String minutes = await PrayersName().getMinutesText();
        notificationTitle = '$prayer $inText $notificationBeforeShuruq $minutes';
      } else {
        String formattedTime = PrayerTimeFormat().getFormattedPrayerTime(prayerTime: time, timeFormat: is24HourFormat, selectedLanguage: appLanguage);
        notificationTitle = '$prayer  $formattedTime';
      }

      if (sound == 'DEFAULT') {
        adhanSound = null;
      } else if (soundType == SoundType.customSound) {
        adhanSound = sound.substring(0, sound.length - 4);
      } else {
        adhanSound = sound;
      }
    }

    bool mute = await DeviceRingtoneMode.isMuted();

    print('is mute: $mute');

    // Assign per-prayer channel ID
    String baseChannelId = prayer.toLowerCase(); // e.g., 'fajr', 'dhuhr'
    String channelName = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan';
    String channelId = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan $sound';

    print(" ----- ------- -- - - - --- -channelId: $channelId");
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(mute ? 'Silent $channelId' : channelId, mute ? 'Silent' : channelName,
        channelDescription: isPreNotification ? 'Pre Adhan notifications for $prayer' : 'Adhan notifications for $prayer',
        importance: Importance.max,
        priority: Priority.high,
        playSound: !isPreNotification || !mute,
        sound: (mute)
            ? const RawResourceAndroidNotificationSound('silent_sound')
            : isPreNotification
                ? null
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

    final NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      notificationTitle,
      mosque,
      platformChannelSpecifics,
    );

    // Remove this fired alarm from the stored list
    await ScheduleThrottleHelper.removeFiredAlarm(id);

    // Only reschedule if needed (throttled to prevent alarm accumulation)
    ScheduleAdhan scheduleAdhan = ScheduleAdhan.instance;
    await scheduleAdhan.scheduleIfNeeded();
  } catch (e, t) {
    print('an error occurs');
    print(t);
    print(e);
  }
}

class ScheduleAdhan {
  // Private constructor
  ScheduleAdhan._privateConstructor() {
    newAlarmIds = [];
    isScheduling = false;
  }

  // Singleton instance
  static final ScheduleAdhan _instance = ScheduleAdhan._privateConstructor();

  // Getter to access the single instance
  static ScheduleAdhan get instance => _instance;

  // The list that should be initialized only once
  late List<String> newAlarmIds;
  late bool isScheduling;

  // Track if reschedule was requested during scheduling
  bool _pendingReschedule = false;

  Future<bool> checkIOSNotificationPermissions() async {
    final iosPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final permissionStatus = await iosPlugin?.checkPermissions();
    if (permissionStatus == null) {
      print('Could not get permission status');
      return false;
    } else {
      print('OverAll: ${permissionStatus.isEnabled}');
      print('Alert: ${permissionStatus.isAlertEnabled}');
      print('Badge: ${permissionStatus.isBadgeEnabled}');
      print('Sound: ${permissionStatus.isSoundEnabled}');
      return permissionStatus.isEnabled && permissionStatus.isAlertEnabled && permissionStatus.isBadgeEnabled && permissionStatus.isSoundEnabled;
    }
  }

  schedule() {
    if (Platform.isAndroid) {
      scheduleAndroid();
    } else if (Platform.isIOS) {
      scheduleIOS();
    }
  }

  flushAlarmIdList() => newAlarmIds = [];

  scheduleAndroid() async {
    print('from schedule');
    if (isScheduling) {
      print("Scheduling in progress, will retry after completion...");
      _pendingReschedule = true;  // Mark for retry instead of dropping
      return;
    }

    isScheduling = true;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Cancel previous alarms with comprehensive cleanup
      List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];
      print('Cancelling ${previousAlarms.length} stored alarms...');

      for (String alarmId in previousAlarms) {
        try {
          int id = int.parse(alarmId);
          await AndroidAlarmManager.cancel(id);
        } catch (e) {
          print('Error cancelling alarm $alarmId: $e');
        }
      }

      // Cancel orphan alarms
      await _cancelOrphanAlarms();

      // Clear stored list
      flushAlarmIdList();
      await prefs.remove('alarmIds');

      // Fetch prayers
      var prayersList = await PrayerService().getPrayers();

      if (prayersList.isEmpty) {
        print('No prayers to schedule');
        return;
      }

      // Fetch settings ONCE before loop
      String minutesToAthan = await PrayersName().getStringText();
      String appLanguage = await PrayersName().getLanguage();
      bool is24HourFormat = await PrayerTimeFormat().get24HoursFormatSetting();

      // Schedule each prayer
      for (var i = 0; i < prayersList.length; i++) {
        var prayer = prayersList[i];

        try {
          await _schedulePreNotification(prayer, prefs, minutesToAthan, appLanguage, is24HourFormat);
          await _scheduleMainNotification(prayer, prefs, appLanguage, is24HourFormat);
        } catch (e, stackTrace) {
          print('Error scheduling ${prayer.prayerName}: $e');
          print(stackTrace);

          // Check if we hit the 500 limit
          if (e.toString().contains('Maximum limit of concurrent alarms')) {
            print('CRITICAL: Hit 500 alarm limit. Attempting emergency cleanup...');
            await _emergencyAlarmCleanup();
            // Don't continue scheduling - let next cycle retry
            break;
          }
        }
      }

      // Save the new alarm IDs
      await prefs.setStringList('alarmIds', newAlarmIds);
      print('Scheduled ${newAlarmIds.length} alarms: $newAlarmIds');

    } catch (e, stackTrace) {
      print('Critical error in scheduleAndroid: $e');
      print(stackTrace);
      // Report to Sentry/Crashlytics here
    } finally {
      isScheduling = false;

      // Check if another schedule was requested while we were busy
      if (_pendingReschedule) {
        _pendingReschedule = false;
        // Add small delay to prevent tight loop
        await Future.delayed(Duration(milliseconds: 500));
        schedule();
      }
    }
  }

  /// Emergency cleanup when 500 limit is reached
  Future<void> _emergencyAlarmCleanup() async {
    print('Starting emergency alarm cleanup...');

    // Cancel ALL possible alarm IDs in our ID space
    // New format range: 202401010 to 202512316 (current year)
    int currentYear = DateTime.now().year;

    for (int month = 1; month <= 12; month++) {
      for (int day = 1; day <= 31; day++) {
        for (int prayer = 0; prayer <= 6; prayer++) {
          int alarmId = currentYear * 100000 + month * 1000 + day * 10 + prayer;
          int preAlarmId = 1000000000 + alarmId;

          try {
            await AndroidAlarmManager.cancel(alarmId);
            await AndroidAlarmManager.cancel(preAlarmId);
          } catch (e) {
            // Continue cleanup even if individual cancel fails
          }
        }
      }
    }

    // Also clean legacy IDs
    await _cancelLegacyAlarms();

    print('Emergency cleanup complete');
  }

  scheduleIOS() async {
    try {
      // Clear all scheduled notifications
      await flutterLocalNotificationsPlugin.cancelAll();
      print('Cleared previous Notifications');

      // Retrieve SharedPreferences and prayers list
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var prayersList = await PrayerService().getPrayers();
      int i = 0, j = 0;

      if (prayersList.isEmpty) {
        return; // Exit early if there are no prayers
      } else {
        // Loop to schedule up to 63 notifications
        while (i < prayersList.length && j < 63) {
          var prayer = prayersList[i];
          int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');

          // Fetch prayer translations and preset strings
          String translatedPrayerName = prayer.prayerName ?? 'Unknown';
          String minutesToAthan = await PrayersName().getStringText();
          String inText = await PrayersName().getInText();
          String minutes = await PrayersName().getMinutesText();

          // Pre-notification logic
          var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));

          /// PRE NOTIFICATION
          if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
            String title = '${prayer.notificationBeforeAthan} $minutesToAthan $translatedPrayerName';
            await iosNotificationSchedular(
              int.parse(("1${prayer.alarmId}")),
              preNotificationTime,
              title,
              prayer.mosqueName,
              null,
            );
            print('Pre Notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: ${1 + prayer.alarmId}');
            j++;
          }

          // Main Athan notification logic
          String prayerTime = DateFormat('HH:mm').format(prayer.time!);
          DateTime notificationTime = prayer.time!;
          //Fetch App Language
          String languageCode = await PrayersName().getLanguage();
          //Fetch App time format
          bool is24HourFormat = await PrayerTimeFormat().get24HoursFormatSetting();
          // Make notification time on the base of TIME FORMAT and SELECTED LANGUAGE from APP
          String formatedPrayerTime = PrayerTimeFormat().getFormattedPrayerTime(prayerTime: prayerTime, timeFormat: is24HourFormat, selectedLanguage: languageCode);
          String notificationTitle = '$translatedPrayerName $formatedPrayerTime';
          int notificationBeforeShuruq;

          // Handle Shuruq timing if the prayer is Fajr (index == 1)
          if (index == 1) {
            notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;
            notificationTime = prayer.time!.subtract(Duration(minutes: notificationBeforeShuruq));
            notificationTitle = '$translatedPrayerName $inText $notificationBeforeShuruq $minutes';
          }

          if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
            if (prayer.soundType == SoundType.systemSound.name) {
              String? soundFile;

              if (prayer.sound?.isNotEmpty == true) {
                soundFile = await PrayerService().getDeviceSound(prayer.sound ?? "");
              }

              await iosNotificationSchedular(
                prayer.alarmId,
                notificationTime,
                notificationTitle,
                prayer.mosqueName,
                soundFile ?? prayer.sound,
              );
            } else {
              await iosNotificationSchedular(
                prayer.alarmId,
                notificationTime,
                notificationTitle,
                prayer.mosqueName,
                prayer.sound,
              );
            }
            print('Notification scheduled for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
            j++;
            // }
          }

          // Move to the next prayer
          i++;
        }
      }
    } catch (e, s) {
      // Enhanced error logging
      print('Error in scheduleIOS: $e');
      print('$s');
    }
    List<PendingNotificationRequest> allPendingNotification = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    print('All scheduling notifications length:  ${allPendingNotification.length}');
    for (var element in allPendingNotification) {
      print('element length:  ${element.title} , body: ${element.payload}');
      print('------------------------------------------------------------------------------------------------------');
    }
  }

  Future<void> initAlarmManager() async {
    await AndroidAlarmManager.initialize();
  }

  Future<void> init() async {
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> iosNotificationSchedular(int? id, DateTime date, String? title, String? body, String? soundId) async {
    print('--------------------------------------------------schedule sound id : $soundId --------------------------------------------------');
    try {
      final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
          sound: soundId == 'DEFAULT' ? null : soundId, presentSound: true, presentAlert: true, presentBadge: true, interruptionLevel: InterruptionLevel.critical);

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
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
    } catch (e, s) {
      print('ERROR: $e');
      print('stack trace: $s');
    }
  }

  /// Cancels potential orphan alarms from the past 7 days
  /// This is a recovery mechanism for alarms that weren't properly tracked
  Future<void> _cancelOrphanAlarms() async {
    print('Scanning for orphan alarms...');
    int cancelledCount = 0;

    // Check past 7 days and next 7 days
    for (int dayOffset = -7; dayOffset <= 7; dayOffset++) {
      DateTime date = DateTime.now().add(Duration(days: dayOffset));

      // For each prayer (0-6)
      for (int prayerIndex = 0; prayerIndex <= 6; prayerIndex++) {
        // Generate the expected alarm ID for this date/prayer
        int alarmId = date.year * 100000 + date.month * 1000 + date.day * 10 + prayerIndex;
        int preAlarmId = 1000000000 + alarmId;

        try {
          await AndroidAlarmManager.cancel(alarmId);
          await AndroidAlarmManager.cancel(preAlarmId);
          cancelledCount += 2;
        } catch (e) {
          // Ignore errors - alarm may not exist
        }
      }
    }

    // Only cancel legacy format IDs if NOT migrated yet
    // After migration, no legacy alarms exist - skip 70,000 iterations
    bool migrated = await AlarmMigrationHelper.isMigrated();
    if (!migrated) {
      print('Not migrated yet - cleaning legacy alarms...');
      await _cancelLegacyAlarms();
      await AlarmMigrationHelper.markMigrated();
    }

    print('Orphan alarm scan complete. Attempted to cancel $cancelledCount potential alarms.');
  }

  /// Cancels alarms created with the old buggy ID format
  /// Optimized: ~5,200 parallel calls instead of 140,000 sequential
  Future<void> _cancelLegacyAlarms() async {
    await LegacyAlarmCleaner.cancelAll();
  }

  /// Schedule pre-notification for a prayer
  Future<void> _schedulePreNotification(
    dynamic prayer,
    SharedPreferences prefs,
    String minutesToAthan,
    String appLanguage,
    bool is24HourFormat,
  ) async {
    var preNotificationTime = prayer.time!.subtract(
      Duration(minutes: prayer.notificationBeforeAthan),
    );

    if (prayer.notificationBeforeAthan != 0 &&
        preNotificationTime.isAfter(DateTime.now())) {
      // Generate pre-notification ID using new format
      int preId = AlarmIdGenerator.generatePreNotification(prayer.alarmId);
      newAlarmIds.add(preId.toString());

      await AndroidAlarmManager.oneShotAt(
        preNotificationTime,
        preId,
        ringAlarm,
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
          'scheduledTime': preNotificationTime.toIso8601String(),
        },
      );
      print('Pre Notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: $preId');
    }
  }

  /// Schedule main notification for a prayer
  Future<void> _scheduleMainNotification(
    dynamic prayer,
    SharedPreferences prefs,
    String appLanguage,
    bool is24HourFormat,
  ) async {
    String prayerTime = DateFormat('HH:mm').format(prayer.time!);
    DateTime notificationTime;
    int notificationBeforeShuruq;

    int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');

    if (index == 1) {
      // Shuruq
      notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;
      notificationTime = prayer.time!.subtract(
        Duration(minutes: notificationBeforeShuruq),
      );
    } else {
      notificationTime = prayer.time!;
      notificationBeforeShuruq = 0;
    }

    if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
      newAlarmIds.add(prayer.alarmId.toString());

      await AndroidAlarmManager.oneShotAt(
        notificationTime,
        prayer.alarmId,
        ringAlarm,
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
          'scheduledTime': notificationTime.toIso8601String(),
        },
      );
      print('Notification scheduled for ${prayer.prayerName} at: $notificationTime Id: ${prayer.alarmId}');
    }
  }

  /// Schedule only if needed - prevents excessive rescheduling
  /// Call this from ringAlarm instead of schedule() directly
  Future<void> scheduleIfNeeded() async {
    // Check if we scheduled recently
    bool shouldSchedule = await ScheduleThrottleHelper.shouldSchedule();
    if (!shouldSchedule) {
      return;
    }

    // Check how many alarms are remaining
    bool runningLow = await ScheduleThrottleHelper.isRunningLowOnAlarms(threshold: 3);
    if (!runningLow) {
      print('Skipping schedule - sufficient alarms remaining');
      return;
    }

    print('Scheduling needed - running low on alarms');
    await ScheduleThrottleHelper.recordScheduleTime();
    await schedule();
  }

  /// Force a full reschedule (bypasses throttling)
  Future<void> forceSchedule() async {
    await ScheduleThrottleHelper.recordScheduleTime();
    await schedule();
  }

  /// Check if migration is needed (for informational purposes)
  /// Migration now happens automatically during first schedule
  Future<bool> needsMigration() async {
    if (!Platform.isAndroid) return false;
    return !(await AlarmMigrationHelper.isMigrated());
  }
}
