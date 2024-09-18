// ignore_for_file: avoid_print, unused_local_variable

library mobile_app_notifications;

import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  print('from ringAlarm');
  int index = data['index'];
  String sound = data['sound'];
  String mosque = data['mosque'];
  String prayer = data['prayer'];
  String time = data['time'];
  bool isPreNotification = data['isPreNotification'];
  String minutesToAthan = data['minutesToAthan'];
  int notificationBeforeShuruq = data['notificationBeforeShuruq'];

  String? adhanSound;
  String notificationTitle;
  try {
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
        notificationTitle = '$prayer  $time';
      }

      if (sound == 'DEFAULT') {
        adhanSound = null;
      } else {
        adhanSound = 'resource://raw/${sound.substring(0, sound.length - 4)}';
      }
    }
    print('adhan sound: $adhanSound');
    AwesomeNotifications().initialize('resource://drawable/logo', [
      NotificationChannel(
        channelKey: isPreNotification ? 'pre_notif' : adhanSound ?? 'DEFAULT',
        channelName: 'mawaqit',
        channelDescription: 'mawaqit_channel',
        importance: NotificationImportance.Max,
        defaultColor: const Color(0xFF9D50DD),
        ledColor: Colors.white,
        playSound: true,
        soundSource: isPreNotification ? null : adhanSound,
        enableVibration: false,
        icon: 'resource://drawable/logo',
        onlyAlertOnce: true,
        criticalAlerts: true,
        defaultRingtoneType: DefaultRingtoneType.Notification,
      )
    ]);
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: isPreNotification ? 'pre_notif' : adhanSound ?? 'DEFAULT',
        title: notificationTitle,
        body: mosque,
        category: NotificationCategory.Reminder,
        criticalAlert: true,
        wakeUpScreen: true,
        largeIcon: 'resource://drawable/logo',
        icon: 'resource://drawable/logo',
      ),
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
      int index = getPrayerIndex(prayer.prayerName!);

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
    flutterLocalNotificationsPlugin.cancelAll();
    print('Cleared previous Notificatoins');

    SharedPreferences prefs = await SharedPreferences.getInstance();
    var prayersList = await PrayerService().getPrayers();
    int i = 0, j = 0;
    if (prayersList.isEmpty) {
      return;
    } else {
      while (j < 63) {
        var prayer = prayersList[i];
        int index = getPrayerIndex(prayer.prayerName!);

        String translatedPrayerName = await PrayersName().getPrayerName(index);
        String minutesToAthan = await PrayersName().getStringText();
        String inText = await PrayersName().getInText();
        String minutes = await PrayersName().getMinutesText();

        //for pre notification
        var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));
        if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
          String title = '${prayer.notificationBeforeAthan.toString()} $minutesToAthan $translatedPrayerName';
          iosNotificationSchedular(
            int.parse(("1${prayer.alarmId}")),
            preNotificationTime,
            title,
            prayer.mosqueName,
            null,
          );
          print('Pre Notification scheduled for ${prayer.prayerName} at : $preNotificationTime Id: ${1 + prayer.alarmId}');

          j++;
        }

        //for Athan Notification
        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        DateTime notificationTime;
        String notificationTitle;
        int notificationBeforeShuruq;

        if (index == 1) {
          notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;
          notificationTime = prayer.time!.subtract(Duration(minutes: notificationBeforeShuruq));
          notificationTitle = '$translatedPrayerName $inText $notificationBeforeShuruq $minutes';
        } else {
          notificationBeforeShuruq = 0;
          notificationTime = prayer.time!;
          notificationTitle = '$translatedPrayerName $prayerTime';
        }

        // if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
        //   iosNotificationSchedular(prayer.alarmId, notificationTime, notificationTitle, prayer.mosqueName, prayer.sound);
        //   print('Notification scheduled for ${prayer.prayerName} at : $notificationTime Id: ${prayer.alarmId}');
        //   j++;
        // }

        if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
          // Schedule 5 notifications with 10-second intervals for Athan notification
          for (int count = 0; count < 5; count++) {
            DateTime scheduledTime = notificationTime.add(Duration(seconds: count * 10));
            iosNotificationSchedular(
              prayer.alarmId + count,
              scheduledTime,
              notificationTitle,
              prayer.mosqueName,
              prayer.sound,
            );
            print('Notification $count scheduled for ${prayer.prayerName} at : $scheduledTime Id: ${prayer.alarmId}');
            j++;
          }
        }
        i++;
      }
    }
  }

  Future<void> initAlarmManager() async {
    await AndroidAlarmManager.initialize();
  }

  var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> iosNotificationSchedular(
    int? id,
    DateTime date,
    String? title,
    String? body,
    String? soundId,
  ) async {
    print('--------------------------------------------------sound id : $soundId --------------------------------------------------');
    try {
      final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
        sound: soundId == 'DEFAULT' ? null : soundId,
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      );

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
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
    } on Exception catch (e) {
      print('ERROR: $e');
    }
  }
}
