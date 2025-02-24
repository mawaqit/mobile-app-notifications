// prayer_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/mosque/detailed_mosque.dart';
import 'models/notification/notification_info_model.dart';
import 'models/prayers/prayer_notification.dart';

class PrayerService {
  final List<String> prayerKeys = [
    'FAJR_NOTIFICATION',
    'SHURUQ_NOTIFICATION',
    'DUHR_NOTIFICATION',
    'ASR_NOTIFICATION',
    'MAGRIB_NOTIFICATION',
    'ISHAA_NOTIFICATION',
    'IMSAK_NOTIFICATION',
  ];

  bool check(PrayerNotification obj) {
    if (obj.notificationSound == 'SILENT' && obj.notificationBeforeAthan == 0) {
      return false;
    } else if (obj.notificationSound == null && obj.notificationBeforeAthan == null) {
      return false;
    } else {
      return true;
    }
  }

  Future<List<NotificationInfoModel>> getPrayers() async {
    List<NotificationInfoModel> prayersList = [];
    var scheduledCount = 0;
    for (var key in prayerKeys) {
      var obj = await PrayerNotificationService().getPrayerNotificationFromDB(key);
      if (check(obj)) {
        scheduledCount++;
      }
    }

    if (scheduledCount == 0) {
      return prayersList;
    }

    int i = -1;
    while (prayersList.length < (Platform.isIOS ? 70 : 10)) {
      i++;
      for (var key in prayerKeys) {
        var obj = await PrayerNotificationService().getPrayerNotificationFromDB(key);
        var index = prayerKeys.indexOf(key);
        if (check(obj)) {
          final mosque = await getMosque(obj.mosqueUuid ?? '');

          var time = getPrayerTime(mosque, key, time: DateTime.now().add(Duration(days: i)));
          var notificationData = await getPrayerDataByIndex(mosque, index);
          var prayerName = _getPrayerName(index);

          // String indexStr = index.toString(), dayStr = time!.day.toString(), monthStr = time.month.toString();
          // String str = indexStr + dayStr + monthStr;
          // int alarmId = int.parse(str);

          int alarmId = makeAlarmId();
          // return alarmId;
          print('Alarm ID: $alarmId');

          NotificationInfoModel prayer = NotificationInfoModel(
              mosqueName: mosque.name,
              sound: obj.notificationSound,
              prayerName: prayerName,
              time: time,
              notificationBeforeAthan: notificationData?.notificationBeforeAthan ?? 0,
              alarmId: alarmId,
              soundType: obj.soundType.name);

          prayersList.add(prayer);
        }
      }
    }
    prayersList.removeWhere((element) {
      return element.time!.isBefore(DateTime.now());
    });
    prayersList.sort(
      (a, b) => a.time!.millisecondsSinceEpoch.toString().compareTo(b.time!.millisecondsSinceEpoch.toString()),
    );
    prayersList = prayersList.sublist(0, Platform.isIOS ? 63 : 5);
    return prayersList;
  }

  Future<PrayerNotification?> getPrayerDataByIndex(DetailedMosque? mosque, int index) async {
    final nextPrayerKey = prayerKeys[index];
    final notificationData = await PrayerNotificationService().getPrayerNotificationFromDB(nextPrayerKey);

    return notificationData;
  }

  String _getPrayerName(int index) {
    switch (index) {
      case 0:
        return 'Fajr';
      case 1:
        return 'Shuruq';
      case 2:
        return 'Duhr';
      case 3:
        return 'Asr';
      case 4:
        return 'Maghrib';
      case 5:
        return 'Isha';
      case 6:
        return 'Imsak';
      default:
        return 'Unknown';
    }
  }

  DateTime? getPrayerTime(DetailedMosque mosque, String key, {DateTime? time}) {
    var now = time ?? DateTime.now();

    var calendar = mosque.calendar;

    var index = prayerKeys.indexOf(key);

    if (index == 6) {
      var calendar = mosque.imsakCalendar!;

      var monthCalendar = (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
      var prayerTime = monthCalendar[now.day - 1];

      var todayTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(prayerTime.toString().split(':')[0]),
        int.parse(prayerTime.toString().split(':')[1]),
      );

      return todayTime;
    }
    if (calendar != null) {
      var monthCalendar = (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
      var todayTimes = monthCalendar[now.day - 1];

      var prayerTime = todayTimes[index];

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

  Future<DetailedMosque> getMosque(String uuid) async {
    final db = await SharedPreferences.getInstance();
    final data = db.getString(uuid) ?? jsonEncode({});
    final Map<String, dynamic> mosqueJson = jsonDecode(data);
    final mosque = DetailedMosque.fromJson(mosqueJson);

    return mosque;
  }

  Future<String?> getDeviceSound(String path) async {
    try {
      const savedAudio = 'SAVED_AUDIO';
      final prefs = await SharedPreferences.getInstance();
      final savedFilesJson = prefs.getString(savedAudio) ?? '';

      if (savedFilesJson.isNotEmpty) {
        final savedFiles = List<Map<String, String>>.from(
          jsonDecode(savedFilesJson).map((e) => Map<String, String>.from(e)),
        );

        for (var file in savedFiles) {
          if (file["path"] == path && await fileExists(file["path"]!)) {
            return file['name'];
          }
        }
      }
    } catch (e) {
      debugPrint("Exception in getDeviceSound: $e");
    }
    return null;
  }

  Future<bool> fileExists(String path) async {
    try {
      File file = File(path);
      RandomAccessFile raf = file.openSync();
      raf.closeSync();
      return true;
    } catch (e) {
      return false;
    }
  }

  int makeAlarmId(){
    var _uuid = Uuid();
    String uuid = _uuid.v4();
    int alarmId = int.parse(uuid.substring(0, 8), radix: 16);
    return alarmId;
  }
}
