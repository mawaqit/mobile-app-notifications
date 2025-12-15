/// Alarm management helpers for fixing 500 alarm limit issue

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Constants
class AlarmConstants {
  static const Duration minScheduleInterval = Duration(minutes: 30);
  static const String lastScheduleTimeKey = 'last_schedule_time';
  static const String migrationKey = 'alarm_system_v2_migrated';
  static const String alarmIdsKey = 'alarmIds';
  static const int preNotificationOffset = 1000000000;

  /// Max minutes late before notification is considered stale
  static const int maxStalenessMinutes = 10;
}

/// Alarm ID generator
class AlarmIdGenerator {
  /// Format: YYYYMMDDP (e.g., 202412150 = Dec 15, 2024, Fajr)
  static int generate(int prayerIndex, DateTime time) {
    return time.year * 100000 + time.month * 1000 + time.day * 10 + prayerIndex;
  }

  static int generatePreNotification(int baseAlarmId) {
    return AlarmConstants.preNotificationOffset + baseAlarmId;
  }
}

/// Legacy alarm cleanup (optimized - only ~5,200 calls instead of 140,000)
class LegacyAlarmCleaner {
  /// Cancel legacy alarms using parallel execution
  /// Old format was: index + day + month (only ~2,600 valid combinations)
  static Future<void> cancelAll() async {
    print('Cancelling legacy alarms (optimized)...');

    List<Future<void>> futures = [];

    // Generate only valid old-format IDs (7 prayers × 31 days × 12 months)
    for (int prayer = 0; prayer <= 6; prayer++) {
      for (int day = 1; day <= 31; day++) {
        for (int month = 1; month <= 12; month++) {
          String idStr = '$prayer$day$month';
          int legacyId = int.parse(idStr);
          int preLegacyId = int.parse('1$idStr');

          futures.add(AndroidAlarmManager.cancel(legacyId));
          futures.add(AndroidAlarmManager.cancel(preLegacyId));
        }
      }
    }

    // Execute all in parallel
    await Future.wait(futures, eagerError: false);
    print('Legacy cleanup done (${futures.length} IDs)');
  }
}

/// Schedule throttling
class ScheduleThrottleHelper {
  static Future<bool> shouldSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(AlarmConstants.lastScheduleTimeKey);

    if (lastMs == null) return true;

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
    return elapsed >= AlarmConstants.minScheduleInterval;
  }

  static Future<bool> isRunningLowOnAlarms({int threshold = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(AlarmConstants.alarmIdsKey) ?? [];
    return ids.length < threshold;
  }

  static Future<void> recordScheduleTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AlarmConstants.lastScheduleTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<int> removeFiredAlarm(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(AlarmConstants.alarmIdsKey) ?? [];
    ids.remove(alarmId.toString());
    await prefs.setStringList(AlarmConstants.alarmIdsKey, ids);
    return ids.length;
  }
}

/// Migration helper
class AlarmMigrationHelper {
  static Future<bool> isMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AlarmConstants.migrationKey) ?? false;
  }

  static Future<void> markMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AlarmConstants.migrationKey, true);
  }
}

/// Notification staleness checker
class NotificationFreshnessChecker {
  /// Returns true if notification should be shown (not stale)
  /// Returns false if notification is too old (time was manually changed)
  static bool isFresh(String? scheduledTimeStr) {
    if (scheduledTimeStr == null) return true;

    try {
      final scheduled = DateTime.parse(scheduledTimeStr);
      final staleness = DateTime.now().difference(scheduled);

      if (staleness.inMinutes > AlarmConstants.maxStalenessMinutes) {
        print('Stale notification - ${staleness.inMinutes} min late, skipping');
        return false;
      }
      return true;
    } catch (e) {
      return true; // Show if can't parse
    }
  }
}
