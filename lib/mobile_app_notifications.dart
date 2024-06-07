// ignore_for_file: avoid_print

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

  String? adhanSound;
  try {
    if (isPreNotification) {
      print('for pre notification');
    } else {
      print('for adhan notification');
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
        title: isPreNotification
            ? '$time $minutesToAthan $prayer'
            : '$prayer  $time',
        body: mosque,
        category: NotificationCategory.Reminder,
        criticalAlert: true,
        wakeUpScreen: true,
        largeIcon: 'resource://drawable/logo',
        icon: 'resource://drawable/logo',
      ),
    );

    ScheduleAdhan scheduleAdhan = ScheduleAdhan();
    if (!isPreNotification) {
      // scheduleAdhan.schedule();
    }
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
      default:
        return 0;
    }
  }

  final prayerKeys = [
    'FAJR_NOTIFICATION',
    '',
    'DUHR_NOTIFICATION',
    'ASR_NOTIFICATION',
    'MAGRIB_NOTIFICATION',
    'ISHAA_NOTIFICATION',
  ];

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
      if (Platform.isAndroid) {
        //for Pre notification
        if (prayer.notificationBeforeAthan != 0) {
          var id = "1${prayer.alarmId}";
          newAlarmIds.add(id);
          try {
            AndroidAlarmManager.oneShotAt(
                prayer.time!.subtract(
                    Duration(minutes: prayer.notificationBeforeAthan)),
                int.parse(id),
                ringAlarm,
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
                });
            print(
                'Pre Notification scheduled for ${prayer.prayerName} at : ${prayer.time!.subtract(
              Duration(minutes: prayer.notificationBeforeAthan),
            )} Id: $id');
          } catch (e, t) {
            print(t);
            print(e);
          }
        }
        //for Adhan notification
        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        newAlarmIds.add(prayer.alarmId.toString());
        try {
          AndroidAlarmManager.oneShotAt(i == 0 ? DateTime.now().add(Duration(seconds: 10)) : prayer.time!, prayer.alarmId, ringAlarm,
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
              });
        } catch (e, t) {
          print(t);
          print(e);
        }
        print(
            'Notification scheduled for ${prayer.prayerName} at : ${prayer.time} Id: ${prayer.alarmId}');
      }
    }

    await prefs.setStringList('alarmIds', newAlarmIds);
    print(newAlarmIds.toList());
  }

  scheduleIOS() async {
    flutterLocalNotificationsPlugin.cancelAll();
    print('Cleared previous Notificatoins');

    var prayersList = await PrayerService().getPrayers();
    int i = 0, j = 0;

    while (j < 63) {
      var prayer = prayersList[i];
      int index = getPrayerIndex(prayer.prayerName!);

      String translatedPrayerName = await PrayersName().getPrayerName(index);
      String minutesToAthan = await PrayersName().getStringText();

      //for pre notification
      if (prayer.notificationBeforeAthan != 0) {
        String title =
            '${prayer.notificationBeforeAthan.toString()} $minutesToAthan $translatedPrayerName';
        iosNotificationSchedular(
          int.parse(("1${prayer.alarmId}")),
          prayer.time!
              .subtract(Duration(minutes: prayer.notificationBeforeAthan)),
          title,
          prayer.mosqueName,
          null,
        );
        print(
            'Pre Notification scheduled for ${prayer.prayerName} at : ${prayer.time!.subtract(
          Duration(minutes: prayer.notificationBeforeAthan),
        )} Id: ${1 + prayer.alarmId}');

        j++;
      }

      //for Athan Notification
      String prayerTime = DateFormat('HH:mm').format(prayer.time!);
      iosNotificationSchedular(prayer.alarmId, prayer.time!,
          '$translatedPrayerName $prayerTime', prayer.mosqueName, prayer.sound);
      print(
          'Notification scheduled for ${prayer.prayerName} at : ${prayer.time} Id: ${prayer.alarmId}');
      j++;
      i++;
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
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
      );
    } on Exception catch (e) {
      print('ERROR: $e');
    }
  }
}
