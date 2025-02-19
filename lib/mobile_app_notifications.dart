// ignore_for_file: avoid_print, unused_local_variable

library mobile_app_notifications;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

import 'models/notification/notification_info_model.dart';

var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  print('from ringAlarm');
  int index = data['index'];
  String sound = data['sound'];
  String mosque = data['mosque'];
  String prayer = data['prayer'];
  String time = data['time'];
  SoundType soundType = SoundType.values.firstWhere((e) => e.name == data['sound_type']);
  bool isPreNotification = data['isPreNotification'];
  String minutesToAthan = data['minutesToAthan'];
  int notificationBeforeShuruq = data['notificationBeforeShuruq'];

  String? adhanSound;
  String notificationTitle;
  try {
    String formattedTime = await PrayerTimeFormat().getFormattedPrayerTime(time);

    if (isPreNotification) {
      print('for pre notification');
      notificationTitle = '$time $minutesToAthan $prayer';
    } else {
      print('for adhan notification');
      if (notificationBeforeShuruq != 0) {
        String inText = await PrayersName().getInText();
        String minutes = await PrayersName().getMinutesText();
        print('notificationBeforeShuruq : $notificationBeforeShuruq');
        notificationTitle = '$prayer $inText $notificationBeforeShuruq $minutes';
      } else {
        print('notificationBeforeShuruq : $notificationBeforeShuruq');
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
    print('adhan sound: $adhanSound');
    print('sound type from user: $soundType');

    // Assign per-prayer channel ID
    String baseChannelId = prayer.toLowerCase(); // e.g., 'fajr', 'dhuhr'
    String channelId = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan';

    print(" ----- ------- -- - - - --- -channelId: $channelId");
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      channelId,
      channelId,
      channelDescription: isPreNotification ? 'Pre Adhan notifications for $prayer' : 'Adhan notifications for $prayer',
      importance: Importance.max,
      priority: Priority.high,
      playSound: !isPreNotification,
      sound: isPreNotification
          ? null
          : soundType == SoundType.customSound
              ? RawResourceAndroidNotificationSound(adhanSound)
              : UriAndroidNotificationSound(adhanSound ?? ''),
      enableVibration: true,
      largeIcon: const DrawableResourceAndroidBitmap('logo'),
      icon: 'logo',
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

    ScheduleAdhan scheduleAdhan = ScheduleAdhan();
    scheduleAdhan.schedule();
  } catch (e, t) {
    print('an error occurs');
    print(t);
    print(e);
  }
}

class ScheduleAdhan {
  int getPrayerIndex(String prayer) {
    switch (prayer) {
      case 'Fajr':
        return 0;
      case 'Duhr':
        return 2;
      case 'Asr':
        return 3;
      case 'Maghrib':
        return 4;
      case 'Isha':
        return 5;
      case 'Shuruq':
        return 1;
      case 'Imsak':
        return 6;
      default:
        return 0;
    }
  }

  final prayerKeys = [
    'FAJR_NOTIFICATION',
    'SHURUQ_NOTIFICATION',
    'DUHR_NOTIFICATION',
    'ASR_NOTIFICATION',
    'MAGRIB_NOTIFICATION',
    'ISHAA_NOTIFICATION',
    'IMSAK_NOTIFICATION',
  ];

  int generateSixDigitRandom() {
    math.Random random = math.Random();
    return 10000000 + random.nextInt(90000000); // Ensures an 8-digit number
  }

  Future<void> showSilentNotification({required String prayer, bool isPreNotification = false}) async {
    String baseChannelId = prayer.toLowerCase(); // e.g., 'fajr', 'dhuhr'
    String channelId = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan';
    print('Unique channel name  :  $channelId');

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelId,
      channelDescription: isPreNotification ? 'Pre Adhan notifications for $prayer' : 'Adhan notifications for $prayer',
      playSound: false,
      // No sound
      enableVibration: false,
      // No vibration
      importance: Importance.low,
      // Low importance hides in the notification bar
      priority: Priority.min,
      // Min priority avoids showing in UI
      visibility: NotificationVisibility.secret, // Hides from the status bar
    );

    NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);
    int id = generateSixDigitRandom();
    print('notification id   :  $id');
    await flutterLocalNotificationsPlugin.show(
      id, // Notification ID
      null, // No title
      null, // No body
      notificationDetails,
    );
  }

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

  scheduleAndroid() async {
    print('from schedule');
    SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];
    for (String alarmId in previousAlarms) {
      int id = int.parse(alarmId);
      await AndroidAlarmManager.cancel(id);
      print('Cancelled Alarm Id: $id');
    }
    await prefs.setStringList('alarmIds', []);

    var prayersList = await PrayerService().getPrayers();

    List<String> newAlarmIds = [];

    for (var i = 0; i < prayersList.length; i++) {
      var prayer = prayersList[i];
      int index = getPrayerIndex(prayer.prayerName ?? '');

      String translatedPrayerName = await PrayersName().getPrayerName(index);
      String minutesToAthan = await PrayersName().getStringText();

      //for Pre notification
      var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));

      if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
        var id = "1${prayer.alarmId}";
        newAlarmIds.add(id);
        try {
          AndroidAlarmManager.oneShotAt(preNotificationTime, int.parse(id), ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'index': index,
                'sound': 'mawaqit_id',
                'mosque': prayer.mosqueName,
                'prayer': translatedPrayerName,
                'time': prayer.notificationBeforeAthan.toString(),
                'isPreNotification': true,
                'minutesToAthan': minutesToAthan,
                'notificationBeforeShuruq': 0,
                'sound_type': prayer.soundType
              });
          print('Pre Notification scheduled for ${prayer.prayerName} at : $preNotificationTime Id: $id');
        } catch (e, t) {
          print(t);
          print(e);
        }
      }
      //for Adhan notification
      String prayerTime = DateFormat('HH:mm').format(prayer.time!);
      DateTime notificationTime;
      int notificationBeforeShuruq;
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
          AndroidAlarmManager.oneShotAt(notificationTime, prayer.alarmId, ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'index': index,
                'sound': prayer.sound,
                'mosque': prayer.mosqueName,
                'prayer': translatedPrayerName,
                'time': prayerTime,
                'isPreNotification': false,
                'minutesToAthan': '',
                'notificationBeforeShuruq': notificationBeforeShuruq,
                'sound_type': prayer.soundType
              });
          print('Notification scheduled for ${prayer.prayerName} at : $notificationTime Id: ${prayer.alarmId}');
          await prefs.setStringList('alarmIds', newAlarmIds);
        } catch (e, t) {
          print(t);
          print(e);
        }
      }
    }

    print(newAlarmIds.toList());
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
          int index = getPrayerIndex(prayer.prayerName!);

          // Fetch prayer translations and preset strings
          String translatedPrayerName = await PrayersName().getPrayerName(index);
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
          String formatedPrayerTime = await PrayerTimeFormat().getFormattedPrayerTime(prayerTime);
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
}
