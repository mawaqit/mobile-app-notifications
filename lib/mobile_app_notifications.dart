library mobile_app_notifications;

import 'dart:io';

import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';

import 'models/prayers/prayer_name.dart';
import 'models/prayers/prayer_notification.dart';
import 'models/prayers/prayer_time_format.dart';
import 'src/adhan_player_channel.dart';
import 'src/android_scheduler.dart' as android;
import 'src/ios_scheduler.dart' as ios;
import 'src/notification_plugin.dart' as plugin;
import 'src/pre_notification.dart';

/// Public entry point for scheduling and managing prayer-time notifications.
/// Implementation lives in [src] — this class is a thin delegating facade.
class ScheduleAdhan {
  ScheduleAdhan._();

  static final ScheduleAdhan instance = ScheduleAdhan._();

  Future<void> init() => plugin.init();

  Future<void> initAlarmManager() => android.initAlarmManager();

  Future<bool> checkIOSNotificationPermissions() =>
      ios.checkIOSNotificationPermissions();

  Future<void> scheduleAndroid() => android.scheduleAndroid();

  Future<void> schedule() async {
    if (Platform.isAndroid) {
      await android.scheduleAndroid();
    } else if (Platform.isIOS) {
      await ios.scheduleIOS();
    }
  }

  /// In-app settings preview (Android). Plays the adhan through the same native
  /// path as a real notification — same stream resolution, volume override and
  /// restore — but without the persistent foreground notification. The caller is
  /// responsible for calling [stopAdhanPreview] on sheet-close / app-background.
  Future<void> previewAdhan({
    required String sound,
    required String soundType,
    required bool playInSilent,
    required int adhanVolume,
    String title = '',
    String body = '',
  }) =>
      previewAdhanNative(
        sound: sound,
        soundType: SoundType.values.firstWhere(
          (e) => e.name == soundType,
          orElse: () => SoundType.customSound,
        ),
        playInSilent: playInSilent,
        adhanVolume: adhanVolume,
        title: title,
        body: body,
      );

  /// Live-adjusts the preview volume on the active stream (no restart).
  Future<void> updatePreviewVolume(int adhanVolume) =>
      updatePreviewVolumeNative(adhanVolume);

  /// Stops the preview (or any native playback) and restores the device volume.
  Future<void> stopAdhanPreview() => stopAdhanNative();
}

// ---------------------------------------------------------------------------
// `ringAlarm` and its helpers are intentionally defined in this library
// (`package:mobile_app_notifications/mobile_app_notifications.dart`) rather
// than in `src/`. `android_alarm_manager_plus` identifies callbacks by the
// hash that `PluginUtilities.getCallbackHandle` derives from the function's
// canonical library URI. Moving `ringAlarm` to a different file would change
// that hash and break every alarm queued by a previous build of the host app
// on upgrade — the OS would fire the alarm and the new build wouldn't
// recognise the handle, so nothing would happen and the adhan would go
// silent. Keep it here.
// ---------------------------------------------------------------------------

const Duration _staleAlarmGracePeriod = Duration(minutes: 10);

int? _readEpochMillis(Map<String, dynamic> data, String key) {
  final dynamic value = data[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

bool _isAlarmStillRelevant(Map<String, dynamic> data) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final scheduledAtMillis = _readEpochMillis(data, 'scheduledAtMillis');
  final prayerAtMillis = _readEpochMillis(data, 'prayerAtMillis');
  final isPreNotification = data['isPreNotification'] == true;

  // Backward compatibility for already-scheduled alarms that don't carry timestamps yet.
  if (scheduledAtMillis == null || prayerAtMillis == null) {
    return true;
  }

  if (isPreNotification) {
    return now >= scheduledAtMillis && now < prayerAtMillis;
  }

  return now >= scheduledAtMillis &&
      now <= prayerAtMillis + _staleAlarmGracePeriod.inMilliseconds;
}

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  // Payload extraction and dispatch live inside the try so a stale alarm
  // scheduled by an older build (missing keys, renamed sound_type enum, etc.)
  // doesn't kill the isolate silently — we'd rather log and drop one cycle
  // than miss every future prayer. The reschedule lives in `finally` so a
  // failed cycle still queues tomorrow's alarms.
  try {
    if (!_isAlarmStillRelevant(data)) {
      Log.w('Skipping stale alarm $id');
      return;
    }
    String sound = (data['sound'] as String?) ?? 'DEFAULT';
    String mosque = (data['mosque'] as String?) ?? '';
    String prayer = (data['prayer'] as String?) ?? '';
    String time = (data['time'] as String?) ?? '';
    SoundType soundType = SoundType.values.firstWhere(
      (e) => e.name == data['sound_type'],
      orElse: () => SoundType.customSound,
    );
    bool isPreNotification = (data['isPreNotification'] as bool?) ?? false;
    String minutesToAthan = (data['minutesToAthan'] as String?) ?? '';
    int notificationBeforeShuruq =
        (data['notificationBeforeShuruq'] as int?) ?? 0;
    String appLanguage = data['appLanguage'] ?? 'en';
    bool is24HourFormat = data['is24HourFormat'] ?? true;
    bool playInSilent = data['playInSilent'] ?? false;
    bool customVolumeEnabled = data['customVolumeEnabled'] ?? false;
    int adhanVolume = data['adhanVolume'] ?? 100;

    String notificationTitle;
    if (isPreNotification) {
      notificationTitle = '$time $minutesToAthan $prayer';
    } else if (notificationBeforeShuruq != 0) {
      String inText = await PrayersName().getInText();
      String minutes =
          await PrayersName().getMinutesText(notificationBeforeShuruq);
      notificationTitle = '$prayer $inText $notificationBeforeShuruq $minutes';
    } else {
      String formattedTime = PrayerTimeFormat().getFormattedPrayerTime(
          prayerTime: time,
          timeFormat: is24HourFormat,
          selectedLanguage: appLanguage);
      notificationTitle = '$prayer  $formattedTime';
    }

    if (isPreNotification) {
      await showPreNotification(id, prayer, notificationTitle, mosque);
    } else {
      // Guard: with POST_NOTIFICATIONS denied, the foreground service still runs
      // and MediaPlayer still plays, but the OS suppresses the notification — the
      // adhan would sound with no visible source. Skip playback so audio stays
      // coupled to a visible notification. Checked before the service starts (not
      // inside it) to avoid the background startForegroundService → startForeground
      // 5s contract. The `finally` below still reschedules tomorrow's alarms.
      if (!await plugin.areNotificationsEnabled()) {
        Log.w('Notifications disabled — skipping adhan playback for $prayer');
        return;
      }
      // Fix A: clear the matching pre-notification (if still in the tray) before
      // the adhan service posts its own notification. Pre-notif ID = adhan ID + 100000.
      try {
        await plugin.flutterLocalNotificationsPlugin.cancel(id + 100000);
      } catch (_) {}
      await playAdhanNative(
        sound: sound,
        soundType: soundType,
        title: notificationTitle,
        body: mosque,
        playInSilent: playInSilent,
        customVolumeEnabled: customVolumeEnabled,
        adhanVolume: adhanVolume,
      );
    }

  } catch (e, t) {
    Log.e("Exception ringAlarm", error: e, stackTrace: t);
  } finally {
    // Always queue tomorrow's alarms — even if this cycle failed, even on
    // stale-alarm early return. Missing this call leaves the user stranded
    // until the next still-queued alarm fires (or app restart).
    ScheduleAdhan.instance.schedule();
  }
}
