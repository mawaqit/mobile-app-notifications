// prayer_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/mosque/detailed_mosque.dart';
import 'models/notification/notification_info_model.dart';
import 'models/prayers/prayer_notification.dart';

class PrayerService {
  final List<String> prayerKeys = [
    'FAJR_NOTIFICATION',
    '',
    'DUHR_NOTIFICATION',
    'ASR_NOTIFICATION',
    'MAGRIB_NOTIFICATION',
    'ISHAA_NOTIFICATION',
    'SHURUQ_NOTIFICATION'
  ];

  Future<List<NotificationInfoModel>> getPrayers() async {
    List<NotificationInfoModel> prayersList = [];
    var scheduledCount = 0;
    for (var key in prayerKeys) {
      var obj =
          await PrayerNotificationService().getPrayerNotificationFromDB(key);
      if (obj.mosqueUuid != null) {
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
        var obj =
            await PrayerNotificationService().getPrayerNotificationFromDB(key);
        var index = prayerKeys.indexOf(key);
        if (obj.mosqueUuid != null) {
          final mosque = await getMosque(obj.mosqueUuid!);

          var time = getPrayerTime(mosque, key,
              time: DateTime.now().add(Duration(days: i)));
          var notificationData = await getPrayerDataByIndex(mosque, index);
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
    prayersList.sort(
      (a, b) => a.time!.millisecondsSinceEpoch
          .toString()
          .compareTo(b.time!.millisecondsSinceEpoch.toString()),
    );
    prayersList = prayersList.sublist(0, Platform.isIOS ? 63 : 5);
    return prayersList;
  }

  Future<PrayerNotification?> getPrayerDataByIndex(
      DetailedMosque? mosque, int index) async {
    final nextPrayerKey = prayerKeys[index];
    final notificationData = await PrayerNotificationService()
        .getPrayerNotificationFromDB(nextPrayerKey);
    if (notificationData.notificationSound != 'SILENT') {
      return notificationData;
    } else {
      print('notitifcation is not allowed for the next adhan');
      return null;
    }
  }

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
      case 6:
        return 'Shuruq';
      default:
        return 'Unknown';
    }
  }

  DateTime? getPrayerTime(DetailedMosque mosque, String key, {DateTime? time}) {
    var now = time ?? DateTime.now();

    var calendar = mosque.calendar;

    if (calendar != null) {
      var monthCalendar =
          (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
      var todayTimes = monthCalendar[now.day - 1];

      var prayerTime = todayTimes[
          prayerKeys.indexOf(key) == 6 ? 1 : prayerKeys.indexOf(key)];

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
}
