import 'package:flutter/services.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';

/// MethodChannel bridge for handing the main iOS athan off to a native
/// AlarmKit-based implementation that plays the full adhan recording.
///
/// The standard `flutter_local_notifications` path (`scheduleIOS`) is capped
/// at ~30 seconds because iOS limits UN notification sounds. When a prayer is
/// flagged with `useFullAdhanIOS == true`, its main athan is omitted from the
/// UN schedule and delivered to native via this channel instead — the native
/// side schedules AlarmKit alarms that play the full audio.
///
/// **Channel:** `mobile_app_notifications/full_adhan_ios`
///
/// **Methods (Dart → native):**
/// * `cancelAllFullAdhan` — no args; cancel every previously-scheduled full
///   adhan. Called at the start of each scheduling pass, mirroring
///   `flutterLocalNotificationsPlugin.cancelAll()`.
/// * `scheduleFullAdhan` — args: `{ "prayers": [<payload>, ...] }`. Schedule
///   the listed prayers. See [_FullAdhanPayload] for the per-prayer shape.
///
/// **Per-prayer payload (`Map<String, dynamic>`):**
/// ```
/// {
///   "alarmId":         int,    // unique id, also used for cancellation
///   "fireDateMillis":  int,    // epoch ms when the adhan should fire
///   "prayerIndex":     int,    // 0=Fajr 1=Shuruq 2=Duhr 3=Asr 4=Maghrib 5=Isha 6=Imsak
///   "title":           String, // pre-formatted, e.g. "Fajr 05:12"
///   "body":            String, // mosque name
///   "soundAssetId":    String, // path/filename of the adhan audio
///   "soundType":       String, // "customSound" | "systemSound" | "none"
/// }
/// ```
///
/// Pre-notifications (the "X minutes before athan" reminders) are NOT routed
/// through this channel — they continue to use the UN notification path.
class FullAdhanIOSChannel {
  FullAdhanIOSChannel._();

  static const String channelName = 'mobile_app_notifications/full_adhan_ios';
  static const String _scheduleMethod = 'scheduleFullAdhan';
  static const String _cancelMethod = 'cancelAllFullAdhan';

  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod(_cancelMethod);
    } catch (e, t) {
      Log.e('FullAdhanIOSChannel.cancelAll failed',
          error: e, stackTrace: t);
    }
  }

  static Future<void> schedule(List<Map<String, dynamic>> prayers) async {
    if (prayers.isEmpty) return;
    try {
      await _channel.invokeMethod(_scheduleMethod, {'prayers': prayers});
    } catch (e, t) {
      Log.e('FullAdhanIOSChannel.schedule failed',
          error: e, stackTrace: t);
    }
  }
}
