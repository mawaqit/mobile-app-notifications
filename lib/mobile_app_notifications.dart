library mobile_app_notifications;

import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
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
  Log.i('from ringAlarm');
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

  String? adhanSound;
  String notificationTitle;
  try {
    if (isPreNotification) {
      notificationTitle = '$time $minutesToAthan $prayer';
    } else {
      if (notificationBeforeShuruq != 0) {
        String inText = await PrayersName().getInText();
        String minutes =
            await PrayersName().getMinutesText(notificationBeforeShuruq);
        notificationTitle =
            '$prayer $inText $notificationBeforeShuruq $minutes';
      } else {
        String formattedTime = PrayerTimeFormat().getFormattedPrayerTime(
            prayerTime: time,
            timeFormat: is24HourFormat,
            selectedLanguage: appLanguage);
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

    Log.i('is mute: $mute');

    // Assign per-prayer channel ID
    String baseChannelId = prayer.toLowerCase(); // e.g., 'fajr', 'dhuhr'
    String channelName =
        isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan';
    String channelId = isPreNotification
        ? 'Pre $baseChannelId '
        : '$baseChannelId Adhan $sound';

    Log.t(" ----- ------- -- - - - --- -channelId: $channelId");
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      mute ? 'Silent $channelId' : channelId,
      mute ? 'Silent' : channelName,
      channelDescription: isPreNotification
          ? 'Pre Adhan notifications for $prayer'
          : 'Adhan notifications for $prayer',
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

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      notificationTitle,
      mosque,
      platformChannelSpecifics,
    );

    ScheduleAdhan scheduleAdhan = ScheduleAdhan.instance;
    scheduleAdhan.schedule();
  } catch (e, t) {
    Log.e("Exception ringAlarm", error: e, stackTrace: t);
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

  schedule() {
    if (Platform.isAndroid) {
      scheduleAndroid();
    } else if (Platform.isIOS) {
      scheduleIOS();
    }
  }

  flushAlarmIdList() => newAlarmIds = [];

  /// Migration: Clear all old alarms on first launch after update
  /// This prevents orphan alarms from old ID format
  Future<void> migrateOldAlarmIds() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool migrated = prefs.getBool('alarms_migrated_v2') ?? false;

    if (!migrated && Platform.isAndroid) {
      Log.i('Migrating alarms from old version...');

      // Cancel all tracked alarms
      List<String> oldAlarms = prefs.getStringList('alarmIds') ?? [];
      for (String id in oldAlarms) {
        await AndroidAlarmManager.cancel(int.parse(id));
      }

      // Brute force cancel all possible old-format IDs
      for (int index = 0; index < 7; index++) {
        for (int day = 1; day <= 31; day++) {
          for (int month = 1; month <= 12; month++) {
            // Old main ID format: index + day + month as string
            int oldMainId = int.parse('$index$day$month');
            // Old pre-notification ID format: "1" + mainId
            int oldPreId = int.parse('1$oldMainId');
            await AndroidAlarmManager.cancel(oldMainId);
            await AndroidAlarmManager.cancel(oldPreId);
          }
        }
      }

      // Clear the list
      await prefs.remove('alarmIds');

      // Mark as migrated
      await prefs.setBool('alarms_migrated_v2', true);

      Log.t('Migration complete. Rescheduling with new IDs...');

      // Reschedule with new IDs
      await scheduleAndroid();
    }
  }

  /// Clear all alarms and reschedule - used for 500 error recovery
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

    // Brute force cancel possible IDs
    for (int i = 0; i < 1000000; i += 10000) {
      for (int j = 0; j < 100; j++) {
        await AndroidAlarmManager.cancel(i + j);
      }
    }

    // Clear tracked list
    await prefs.remove('alarmIds');
    flushAlarmIdList();

    Log.i('Cleanup complete.');
  }

  scheduleAndroid() async {
    Log.i('from schedule');
    if (isScheduling) {
      Log.i("Scheduling in progress, please wait until it's completed...");
      return;
    }
    isScheduling = true;
    SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];

    for (String alarmId in previousAlarms) {
      int id = int.parse(alarmId);
      await AndroidAlarmManager.cancel(id);
      Log.i('Cancelled Alarm Id: $id');
    }
    flushAlarmIdList();
    await prefs.remove('alarmIds');
    await prefs.setStringList('alarmIds', []);

    var prayersList = await PrayerService().getPrayers();

    for (var i = 0; i < prayersList.length; i++) {
      var prayer = prayersList[i];

      String minutesToAthan = await PrayersName().getStringText(prayer.notificationBeforeAthan);
      //Fetch App Language
      String appLanguage = await PrayersName().getLanguage();
      //Fetch App time format
      bool is24HourFormat = await PrayerTimeFormat().get24HoursFormatSetting();
      //for Pre notification
      var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));

      if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
        var id = (prayer.alarmId + 100000).toString();
        newAlarmIds.add(id);
        try {
          await AndroidAlarmManager.oneShotAt(preNotificationTime, int.parse(id), ringAlarm,
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
                'is24HourFormat': is24HourFormat
              });
          Log.i('Pre Notification scheduled for ${prayer.prayerName} at : $preNotificationTime Id: $id');
        } catch (e, t) {
          Log.e("Exception oneShotAt", error: e, stackTrace: t);
          // Auto-recover from 500 alarm limit
          if (e.toString().contains('500')) {
            await _clearAllAndReschedule();
            isScheduling = false;
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
        notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;

        notificationTime = prayer.time!.subtract(Duration(minutes: notificationBeforeShuruq));
      } else {
        notificationTime = prayer.time!;
        notificationBeforeShuruq = 0;
      }

      if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
        newAlarmIds.add(prayer.alarmId.toString());
        try {
          await AndroidAlarmManager.oneShotAt(notificationTime, prayer.alarmId, ringAlarm,
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
                'is24HourFormat': is24HourFormat
              });
          Log.i('Sound ${prayer.sound} Notification scheduled for ${prayer.prayerName} at : $notificationTime Id: ${prayer.alarmId}');
        } catch (e, t) {
          Log.e("Exception oneShotAt", error: e, stackTrace: t);
          // Auto-recover from 500 alarm limit
          if (e.toString().contains('500')) {
            await _clearAllAndReschedule();
            isScheduling = false;
            await scheduleAndroid();
            return;
          }
        }
      }
    }
    await prefs.setStringList('alarmIds', newAlarmIds);
    isScheduling = false;

    Log.i(newAlarmIds.toList());
  }

  scheduleIOS() async {
    try {
      // Clear all scheduled notifications
      await flutterLocalNotificationsPlugin.cancelAll();
      Log.i('Cleared previous Notifications');

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
          if (prayer.notificationBeforeAthan != 0 &&
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
            Log.i('Pre Notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: ${prayer.alarmId + 100000}');
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
            notificationBeforeShuruq =
                prefs.getInt('notificationBeforeShuruq') ?? 0;
            notificationTime = prayer.time!
                .subtract(Duration(minutes: notificationBeforeShuruq));
            String minutes =
                await PrayersName().getMinutesText(notificationBeforeShuruq);
            notificationTitle =
                '$translatedPrayerName $inText $notificationBeforeShuruq $minutes';
          }

          if (prayer.sound != 'SILENT' &&
              notificationTime.isAfter(DateTime.now())) {
            if (prayer.soundType == SoundType.systemSound.name) {
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
            } else {
              await iosNotificationSchedular(
                prayer.alarmId,
                notificationTime,
                notificationTitle,
                prayer.mosqueName,
                prayer.sound,
              );
            }
            Log.i('Notification scheduled for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
            j++;
            // }
          }

          // Move to the next prayer
          i++;
        }
      }
    } catch (e, s) {
      Log.e('Error in scheduleIOS: $e', error: e, stackTrace: s);
    }
    List<PendingNotificationRequest> allPendingNotification =
        await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    Log.i('All scheduling notifications length:  ${allPendingNotification.length}');
    for (var element in allPendingNotification) {
      Log.i('element length:  ${element.title} , body: ${element.payload}');
      Log.i('------------------------------------------------------------------------------------------------------');
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

  Future<void> iosNotificationSchedular(int? id, DateTime date, String? title,
      String? body, String? soundId) async {
    Log.i('--------------------------------------------------schedule sound id : $soundId --------------------------------------------------');
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
}
