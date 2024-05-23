library mobile_app_notifications;

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app_notifications/models/mosque/detailed_mosque.dart';
import 'package:mobile_app_notifications/models/notification/notification_info_model.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';

import 'package:shared_preferences/shared_preferences.dart';

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
        id: isPreNotification
            ? index + 10
            : (adhanSound == null ? index + 20 : index + 1),
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
      scheduleAdhan.schedule();
    }
  } catch (e, t) {
    print('an error occurs');
    print(t);
    print(e);
  }
}

class ScheduleAdhan {
  String _getPrayerName(int index) {
    switch (index) {
      case 0:
        return 'Fajr';
      case 2:
        return 'Duhr';
      case 3:
        return 'Asr';
      case 4:
        return 'Maghrib';
      case 5:
        return 'Isha';
      default:
        return 'Unknown';
    }
  }

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
  schedule() async {
    print('from schedule');
    SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];
    for (String alarmId in previousAlarms) {
      int id = int.parse(alarmId);
      await AndroidAlarmManager.cancel(id);
      print('Cancelled Alarm Id: $id');
    }
    await prefs.setStringList('alarmIds', []);

    var prayersList = await getPrayers();
    List<String> newAlarmIds = [];

    for (var i = 0; i < prayersList.length; i++) {
      var prayer = prayersList[i];
      int index = getPrayerIndex(prayer.prayerName!);

      //for Pre notification
      if (Platform.isAndroid) {
        String translatedPrayerName = await PrayersName().getPrayerName(index);
        String minutesToAthan = await PrayersName().getStringText();
        if (prayer.notificationBeforeAthan != 0) {
          newAlarmIds.add((1 + prayer.alarmId).toString());
          try {
            AndroidAlarmManager.oneShotAt(
                prayer.time!.subtract(
                    Duration(minutes: prayer.notificationBeforeAthan)),
                1 + prayer.alarmId,
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
            )} Id: ${1 + prayer.alarmId}');
          } catch (e, t) {
            print(t);
            print(e);
          }
        }
        //for Adhan notification
        String prayerTime = DateFormat('HH:mm').format(prayer.time!);
        newAlarmIds.add(prayer.alarmId.toString());
        try {
          AndroidAlarmManager.oneShotAt(prayer.time!, prayer.alarmId, ringAlarm,
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

  Future<List<NotificationInfoModel>> getPrayers() async {
    List<NotificationInfoModel> prayersList = [];

    var scheduledCount = 0;
    for (var key in prayerKeys) {
      var obj = await PrayerNotification.getPrayerNotificationFromDB(key);
      // if (obj != null && obj.mosqueUuid != null) {
      if (obj.mosqueUuid != null) {
        scheduledCount++;
      }
    }

    if (scheduledCount == 0) {
      return prayersList;
    }

    int i = -1;
    while (prayersList.length < 10) {
      i++;
      for (var key in prayerKeys) {
        var obj = await PrayerNotification.getPrayerNotificationFromDB(key);
        var index = prayerKeys.indexOf(key);

        // if (obj != null && obj.mosqueUuid != null) {
        if (obj.mosqueUuid != null) {
          final mosque = await getMosque(obj.mosqueUuid!);

          var time = _getPrayerTime(mosque, key,
              time: DateTime.now().add(Duration(days: i)));
          var notificationData = await _getPrayerDataByIndex(mosque, index);
          var prayerName = _getPrayerName(index);
          String indexStr = index.toString(),
              dayStr = time!.day.toString(),
              monthStr = time.month.toString();
          String str = indexStr + dayStr + monthStr;
          int alarmId = int.parse(str);
          print('Alarm ID: $alarmId');
          NotificationInfoModel prayer = NotificationInfoModel(
            mosqueName: mosque.name,
            sound: obj.notificationSound,
            prayerName: prayerName,
            time: time,
            notificationBeforeAthan: notificationData!.notificationBeforeAthan!,
            alarmId: alarmId,
          );

          prayersList.add(prayer);
        }
      }
    }
    prayersList.removeWhere((element) {
      return element.time!.isBefore(DateTime.now());
    });
    prayersList = prayersList.sublist(0, 5);
    return prayersList;
  }

  Future<PrayerNotification?> _getPrayerDataByIndex(
      DetailedMosque? mosque, int index) async {
    final nextPrayerKey = prayerKeys[index];
    final notificationData =
        await PrayerNotification.getPrayerNotificationFromDB(nextPrayerKey);
    if (notificationData.notificationSound != 'SILENT') {
      return notificationData;
    } else {
      print('notitifcation is not allowed for the next adhan');
      return null;
    }
  }

  DateTime? _getPrayerTime(DetailedMosque mosque, String key,
      {DateTime? time}) {
    var now = time ?? DateTime.now();

    var calendar = mosque.calendar;

    if (calendar != null) {
      var monthCalendar =
          (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
      var todayTimes = monthCalendar[now.day - 1];

      var prayerTime = todayTimes[prayerKeys.indexOf(key)];

      var todayTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(prayerTime.toString().split(':')[0]),
        int.parse(prayerTime.toString().split(':')[1]),
      );

      return todayTime;
    }

    return null;
  }

  static Future<DetailedMosque> getMosque(String uuid) async {
    final db = await SharedPreferences.getInstance();
    final data = db.getString(uuid) ?? jsonEncode({});
    final Map<String, dynamic> mosqueJson = jsonDecode(data);
    final mosque = DetailedMosque.fromJson(mosqueJson);

    return mosque;
  }
}

