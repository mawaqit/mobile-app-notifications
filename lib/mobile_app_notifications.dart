library mobile_app_notifications;

import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:mobile_app_notifications/helpers/device_ringtone_mode.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

import 'helpers/localization_helper.dart';

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

  Future<bool> scheduleAndroid() async {
    Log.i('scheduleAndroid called');
    if (isScheduling) {
      Log.i("Scheduling already in progress, skipping.");
      return false;
    }
    isScheduling = true;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Cancel all previously scheduled alarms before rebuilding the list
      List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];
      for (String alarmId in previousAlarms) {
        await AndroidAlarmManager.cancel(int.parse(alarmId));
      }
      flushAlarmIdList();
      await prefs.remove('alarmIds');
      await prefs.setStringList('alarmIds', []);

      var prayersList = await PrayerService().getPrayers();

      for (var i = 0; i < prayersList.length; i++) {
        var prayer = prayersList[i];
        String minutesToAthan =
        await PrayersName().getStringText(prayer.notificationBeforeAthan);
        String appLanguage = await PrayersName().getLanguage();
        bool is24HourFormat =
        await PrayerTimeFormat().get24HoursFormatSetting();
        var preNotificationTime = prayer.time!
            .subtract(Duration(minutes: prayer.notificationBeforeAthan));

        if (prayer.notificationBeforeAthan != 0 &&
            preNotificationTime.isAfter(DateTime.now())) {
          var id = (prayer.alarmId + 100000).toString();
          newAlarmIds.add(id);
          try {
            await AndroidAlarmManager.oneShotAt(
              preNotificationTime,
              int.parse(id),
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
              },
            );
          } catch (e, t) {
            Log.e("Exception scheduling pre-notification", error: e, stackTrace: t);
            if (e.toString().contains('500')) {
              await _clearAllAndReschedule();
              isScheduling = false;
              return scheduleAndroid();
            }
            // Any other exception: log and continue to next prayer
            // rather than silently swallowing it
            Log.w('Skipping pre-notification for ${prayer.prayerName}: $e');
          }
        }

        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        DateTime notificationTime;
        int notificationBeforeShuruq;
        int index =
        await PrayersName().getPrayerIndex(prayer.prayerName ?? '');

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
          newAlarmIds.add(prayer.alarmId.toString());
          try {
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
              },
            );
          } catch (e, t) {
            Log.e("Exception scheduling notification", error: e, stackTrace: t);
            if (e.toString().contains('500')) {
              await _clearAllAndReschedule();
              isScheduling = false;
              return scheduleAndroid();
            }
            Log.w('Skipping notification for ${prayer.prayerName}: $e');
          }
        }
      }

      await prefs.setStringList('alarmIds', newAlarmIds);
      Log.i('Scheduled alarm IDs: $newAlarmIds');
      return true;
    } catch (e, t) {
      Log.e("Unexpected error in scheduleAndroid", error: e, stackTrace: t);
      return false;
    } finally {
      isScheduling = false;
    }
  }

  scheduleIOS() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var prayersList = await PrayerService().getPrayers();
      int i = 0, j = 0;

      if (prayersList.isEmpty) return;

      DateTime? lastScheduledTime;

      // Reserve 1 slot (slot 63) for the expiry reminder — hard limit is 62 here
      while (i < prayersList.length && j < 62) {
        var prayer = prayersList[i];
        int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');
        String translatedPrayerName = prayer.prayerName ?? 'Unknown';
        String minutesToAthan =
        await PrayersName().getStringText(prayer.notificationBeforeAthan);
        String inText = await PrayersName().getInText();
        var preNotificationTime = prayer.time!
            .subtract(Duration(minutes: prayer.notificationBeforeAthan));

        if (prayer.notificationBeforeAthan != 0 &&
            preNotificationTime.isAfter(DateTime.now())) {
          String title =
              '${prayer.notificationBeforeAthan} $minutesToAthan $translatedPrayerName';
          await iosNotificationSchedular(prayer.alarmId + 100000,
              preNotificationTime, title, prayer.mosqueName, null);
          lastScheduledTime = preNotificationTime;
          j++;
        }

        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        DateTime notificationTime = prayer.time!;
        String languageCode = await PrayersName().getLanguage();
        bool is24HourFormat = await PrayerTimeFormat().get24HoursFormatSetting();
        String formattedPrayerTime = PrayerTimeFormat().getFormattedPrayerTime(
            prayerTime: prayerTime,
            timeFormat: is24HourFormat,
            selectedLanguage: languageCode);
        String notificationTitle = '$translatedPrayerName $formattedPrayerTime';
        int notificationBeforeShuruq;

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

        if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
          if (prayer.soundType == SoundType.systemSound.name) {
            String? soundFile;
            if (prayer.sound?.isNotEmpty == true) {
              soundFile =
              await PrayerService().getDeviceSound(prayer.sound ?? "");
            }
            await iosNotificationSchedular(prayer.alarmId, notificationTime,
                notificationTitle, prayer.mosqueName, soundFile ?? prayer.sound);
          } else {
            await iosNotificationSchedular(prayer.alarmId, notificationTime,
                notificationTitle, prayer.mosqueName, prayer.sound);
          }
          lastScheduledTime = notificationTime;
          j++;
        }
        i++;
      }

      // Schedule the expiry reminder 2 days before the last notification fires.
      // This uses the reserved 63rd slot and fires even if the app is never opened.
      if (lastScheduledTime != null) {
        final reminderTime =
        lastScheduledTime.subtract(const Duration(days: 2));
        if (reminderTime.isAfter(DateTime.now())) {
          final AppLocalizations localizations =
          await LocalizationHelper.getLocalization();
          await iosNotificationSchedular(
            999998, // fixed ID — will be cancelled on next scheduleIOS() call
            reminderTime,
            "Keep your prayer alerts active", // add this key to your i18n
            "Open the app to refresh your prayer notifications",  // add this key to your i18n
            null,
          );
        }
      }
    } catch (e, s) {
      Log.e('Error in scheduleIOS: $e', error: e, stackTrace: s);
    }

    List<PendingNotificationRequest> allPending =
    await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    Log.i('Scheduled notifications count: ${allPending.length}');
  }

  Future<void> initAlarmManager() async {
    await AndroidAlarmManager.initialize();
  }

  Future<void> init() async {
    // Initialize timezone database once at startup
    tzl.initializeTimeZones();
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
      android: AndroidInitializationSettings('notification_icon'),
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> iosNotificationSchedular(
      int? id, DateTime date, String? title, String? body, String? soundId) async {
    try {
      final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
        sound: soundId == 'DEFAULT' ? null : soundId,
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.critical,
      );
      final platformChannelSpecifics =
      NotificationDetails(iOS: iOSPlatformChannelSpecifics);

      // tz.local is already set in init() — no need to re-initialize here
      final scheduledDate = tz.TZDateTime.from(date, tz.local);
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
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
