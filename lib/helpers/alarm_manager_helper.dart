/// Helper class for managing Android alarm limits and scheduling optimization
///
/// This file contains new functions to fix the 500 alarm limit issue.
/// Created to separate new code from existing functionality.

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Constants for alarm management
class AlarmConstants {
  /// Minimum interval between full schedules to prevent rapid accumulation
  static const Duration minScheduleInterval = Duration(minutes: 30);

  /// Key for storing last schedule time
  static const String lastScheduleTimeKey = 'last_schedule_time';

  /// Key for migration flag
  static const String migrationKey = 'alarm_system_v2_migrated';

  /// Key for storing alarm IDs
  static const String alarmIdsKey = 'alarmIds';

  /// Pre-notification ID offset (adds 1 billion to base ID)
  static const int preNotificationOffset = 1000000000;
}

/// Helper class for alarm ID generation
class AlarmIdGenerator {
  /// Generates a unique, collision-free alarm ID
  /// Format: YYYYMMDDP where P is prayer index (0-6)
  /// Example: 202412150 = 2024-12-15, Fajr (index 0)
  /// Range: 202401010 to 209912316 (fits in 32-bit int)
  static int generate(int prayerIndex, DateTime time) {
    if (prayerIndex < 0 || prayerIndex > 6) {
      throw ArgumentError('Prayer index must be 0-6, got: $prayerIndex');
    }

    int year = time.year;
    int month = time.month;
    int day = time.day;

    // Format: YYYYMMDDP
    return year * 100000 + month * 1000 + day * 10 + prayerIndex;
  }

  /// Generates pre-notification alarm ID by adding offset to base ID
  static int generatePreNotification(int baseAlarmId) {
    return AlarmConstants.preNotificationOffset + baseAlarmId;
  }

  /// Parses alarm ID back to components (for debugging)
  static Map<String, int> parse(int alarmId) {
    // Handle pre-notification IDs
    bool isPreNotification = alarmId >= AlarmConstants.preNotificationOffset;
    if (isPreNotification) {
      alarmId -= AlarmConstants.preNotificationOffset;
    }

    int prayer = alarmId % 10;
    int day = (alarmId ~/ 10) % 100;
    int month = (alarmId ~/ 1000) % 100;
    int year = alarmId ~/ 100000;

    return {
      'year': year,
      'month': month,
      'day': day,
      'prayer': prayer,
      'isPreNotification': isPreNotification ? 1 : 0,
    };
  }
}

/// Helper class for alarm cleanup operations
class AlarmCleanupHelper {
  /// Cancels orphan alarms from a date range
  /// This catches alarms that weren't properly tracked
  static Future<int> cancelOrphanAlarmsInRange({
    required int daysBack,
    required int daysForward,
  }) async {
    print('Scanning for orphan alarms ($daysBack days back, $daysForward days forward)...');
    int cancelledCount = 0;

    for (int dayOffset = -daysBack; dayOffset <= daysForward; dayOffset++) {
      DateTime date = DateTime.now().add(Duration(days: dayOffset));

      for (int prayerIndex = 0; prayerIndex <= 6; prayerIndex++) {
        int alarmId = AlarmIdGenerator.generate(prayerIndex, date);
        int preAlarmId = AlarmIdGenerator.generatePreNotification(alarmId);

        try {
          await AndroidAlarmManager.cancel(alarmId);
          await AndroidAlarmManager.cancel(preAlarmId);
          cancelledCount += 2;
        } catch (e) {
          // Ignore errors - alarm may not exist
        }
      }
    }

    print('Orphan scan complete. Attempted to cancel $cancelledCount potential alarms.');
    return cancelledCount;
  }

  /// Cancels alarms created with the old buggy ID format
  /// Old format: indexStr + dayStr + monthStr (e.g., "0112", "1231")
  static Future<void> cancelLegacyAlarms() async {
    print('Cancelling legacy format alarms...');

    // Old format range: roughly 0 to 63112 (6 prayers * 31 days * 12 months max)
    // We'll cancel in batches to avoid blocking too long
    const int batchSize = 1000;

    for (int start = 0; start <= 70000; start += batchSize) {
      int end = start + batchSize;
      if (end > 70000) end = 70000;

      await _cancelLegacyBatch(start, end);
    }

    print('Legacy alarm cleanup complete.');
  }

  static Future<void> _cancelLegacyBatch(int start, int end) async {
    for (int legacyId = start; legacyId < end; legacyId++) {
      // Skip IDs that look like our new format
      if (legacyId >= 202400000) continue;

      try {
        await AndroidAlarmManager.cancel(legacyId);
        // Also cancel with "1" prefix (old pre-notification format)
        int preId = int.tryParse('1$legacyId') ?? 0;
        if (preId > 0) {
          await AndroidAlarmManager.cancel(preId);
        }
      } catch (e) {
        // Ignore - most won't exist
      }
    }
  }

  /// Emergency cleanup when 500 limit is reached
  /// Cancels ALL possible alarm IDs for current and previous year
  static Future<void> emergencyCleanup() async {
    print('EMERGENCY: Starting comprehensive alarm cleanup...');

    int currentYear = DateTime.now().year;
    int previousYear = currentYear - 1;

    // Cancel current year
    await _cancelYearAlarms(currentYear);

    // Cancel previous year (in case of year boundary issues)
    await _cancelYearAlarms(previousYear);

    // Cancel legacy alarms
    await cancelLegacyAlarms();

    print('EMERGENCY: Cleanup complete.');
  }

  static Future<void> _cancelYearAlarms(int year) async {
    print('Cancelling alarms for year $year...');

    for (int month = 1; month <= 12; month++) {
      for (int day = 1; day <= 31; day++) {
        for (int prayer = 0; prayer <= 6; prayer++) {
          int alarmId = year * 100000 + month * 1000 + day * 10 + prayer;
          int preAlarmId = AlarmConstants.preNotificationOffset + alarmId;

          try {
            await AndroidAlarmManager.cancel(alarmId);
            await AndroidAlarmManager.cancel(preAlarmId);
          } catch (e) {
            // Continue even if individual cancel fails
          }
        }
      }
    }
  }
}

/// Helper class for schedule throttling
class ScheduleThrottleHelper {
  /// Check if enough time has passed since last schedule
  static Future<bool> shouldSchedule() async {
    final prefs = await SharedPreferences.getInstance();

    final lastScheduleMs = prefs.getInt(AlarmConstants.lastScheduleTimeKey);
    if (lastScheduleMs == null) {
      return true; // Never scheduled before
    }

    final lastScheduleTime = DateTime.fromMillisecondsSinceEpoch(lastScheduleMs);
    final timeSinceLastSchedule = DateTime.now().difference(lastScheduleTime);

    if (timeSinceLastSchedule < AlarmConstants.minScheduleInterval) {
      print('Skipping schedule - last scheduled ${timeSinceLastSchedule.inMinutes} minutes ago');
      return false;
    }

    return true;
  }

  /// Check if we're running low on scheduled alarms
  static Future<bool> isRunningLowOnAlarms({int threshold = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmIds = prefs.getStringList(AlarmConstants.alarmIdsKey) ?? [];

    if (alarmIds.length < threshold) {
      print('Running low on alarms - only ${alarmIds.length} remaining');
      return true;
    }

    return false;
  }

  /// Record that scheduling was performed
  static Future<void> recordScheduleTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AlarmConstants.lastScheduleTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Remove a fired alarm from the stored list
  static Future<int> removeFiredalarm(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmIds = prefs.getStringList(AlarmConstants.alarmIdsKey) ?? [];

    alarmIds.remove(alarmId.toString());
    await prefs.setStringList(AlarmConstants.alarmIdsKey, alarmIds);

    print('Removed fired alarm $alarmId. Remaining: ${alarmIds.length}');
    return alarmIds.length;
  }
}

/// Migration helper for users upgrading from buggy version
///
/// Migration happens automatically during first schedule:
/// - _cancelOrphanAlarms() checks if migrated
/// - If not, runs _cancelLegacyAlarms() (70,000 IDs) once
/// - Then marks as migrated
/// - Subsequent schedules skip legacy cleanup (fast)
class AlarmMigrationHelper {
  /// Check if migration has been performed
  static Future<bool> isMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AlarmConstants.migrationKey) ?? false;
  }

  /// Mark migration as complete
  static Future<void> markMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AlarmConstants.migrationKey, true);
  }

  /// Reset migration flag (for testing or re-migration)
  static Future<void> resetMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AlarmConstants.migrationKey);
  }
}
