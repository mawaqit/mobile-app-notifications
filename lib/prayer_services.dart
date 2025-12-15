// prayer_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/localization_helper.dart';
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

  Future<List<NotificationInfoModel>> getPrayers() async {
    List<NotificationInfoModel> prayersList = [];
    var scheduledCount = 0;
    for (var key in prayerKeys) {
      var obj =
          await PrayerNotificationService().getPrayerNotificationFromDB(key);
      if (_check(obj)) {
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
        if (_check(obj)) {
          final mosque = await _getMosque(obj.mosqueUuid ?? '');

          var time = _getPrayerTime(mosque, key,
              time: DateTime.now().add(Duration(days: i)));
          var notificationData = await _getPrayerDataByIndex(mosque, index);
          var prayerName = await _getPrayerName(index);

          int alarmId = _generateAlarmId(index, time!);

          NotificationInfoModel prayer = NotificationInfoModel(
              mosqueName: mosque.name,
              sound: obj.notificationSound,
              prayerName: prayerName,
              time: time,
              notificationBeforeAthan:
                  notificationData?.notificationBeforeAthan ?? 0,
              alarmId: alarmId,
              soundType: obj.soundType.name);

          prayersList.add(prayer);
        }
      }
    }
    prayersList.removeWhere((element) {
      return element.time!.isBefore(DateTime.now());
    });
    // Sort by time using numeric comparison (not string!)
    prayersList.sort((a, b) => a.time!.compareTo(b.time!));
    prayersList = prayersList.sublist(0, Platform.isIOS ? 63 : 5);
    return prayersList;
  }

  bool _check(PrayerNotification obj) {
    if (obj.notificationSound == 'SILENT' && obj.notificationBeforeAthan == 0) {
      return false;
    } else if (obj.notificationSound == null &&
        obj.notificationBeforeAthan == null) {
      return false;
    } else {
      return true;
    }
  }

  Future<PrayerNotification?> _getPrayerDataByIndex(
      DetailedMosque? mosque, int index) async {
    final nextPrayerKey = prayerKeys[index];
    final notificationData = await PrayerNotificationService()
        .getPrayerNotificationFromDB(nextPrayerKey);

    return notificationData;
  }

  Future<String> _getPrayerName(int index) async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    switch (index) {
      case 0:
        return localizations.fajr;
      case 1:
        return localizations.shuruq;
      case 2:
        return localizations.duhr;
      case 3:
        return localizations.asr;
      case 4:
        return localizations.maghrib;
      case 5:
        return localizations.isha;
      case 6:
        return localizations.imsak;
      default:
        return 'Unknown';
    }
  }

  DateTime? _getPrayerTime(DetailedMosque mosque, String key,
      {DateTime? time}) {
    var now = time ?? DateTime.now();

    var calendar = mosque.calendar;

    var index = prayerKeys.indexOf(key);

    if (index == 6) {
      var calendar = mosque.imsakCalendar!;

      var monthCalendar =
          (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
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
      var monthCalendar =
          (calendar[now.month - 1] as Map<String, dynamic>).values.toList();
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

  Future<DetailedMosque> _getMosque(String uuid) async {
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

  /// Generates a unique, collision-free alarm ID
  /// Format: YYYYMMDDP where P is prayer index (0-6)
  /// Example: 202412150 = 2024-12-15, Fajr (index 0)
  /// Range: 202401010 to 209912316 (fits in 32-bit int)
  int _generateAlarmId(int prayerIndex, DateTime time) {
    // Validate prayer index
    if (prayerIndex < 0 || prayerIndex > 6) {
      throw ArgumentError('Prayer index must be 0-6, got: $prayerIndex');
    }

    int year = time.year;
    int month = time.month;
    int day = time.day;

    // Format: YYYYMMDDP
    // Year (4 digits) * 100000 + Month (2 digits) * 1000 + Day (2 digits) * 10 + Prayer (1 digit)
    return year * 100000 + month * 1000 + day * 10 + prayerIndex;
  }

  /// Generates pre-notification alarm ID
  /// Adds 1,000,000,000 to base ID to create separate ID space
  /// Example: Base 202412150 → Pre-notification 1202412150
  int _generatePreNotificationAlarmId(int baseAlarmId) {
    return 1000000000 + baseAlarmId;
  }
}
