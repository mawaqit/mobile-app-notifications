import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';

/// Shared `flutter_local_notifications` instance used by every code path that
/// posts, schedules, cancels, or queries notifications in this package.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Whether the OS will actually display this app's notifications (app-level
/// POST_NOTIFICATIONS on Android 13+). When notifications are denied, the adhan
/// foreground service still runs and MediaPlayer still produces sound, but the
/// notification is suppressed — so a real adhan would play with no visible
/// source. `ringAlarm` uses this to skip playback in that state.
///
/// Fails open (returns `true`) on any error or non-Android platform so a
/// transient failure can never silence the adhan.
Future<bool> areNotificationsEnabled() async {
  try {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? true;
  } catch (e, s) {
    Log.e('Failed reading notification permission — assuming enabled',
        error: e, stackTrace: s);
    return true;
  }
}

Future<void> init() async {
  const initializationSettingsIOS = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );
  const initializationSettings = InitializationSettings(
    iOS: initializationSettingsIOS,
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}
Future<void> cancelAllNotifications() async {
  try {
    await flutterLocalNotificationsPlugin.cancelAll();
    Log.i('All notifications cancelled successfully.');
  } catch (e, s) {
    Log.e('Failed to cancel all notifications', error: e, stackTrace: s);
  }
}

Future<void> deleteOrphanedChannels() async {
  try {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final List<String> prayers = [
      'fajr',
      'shuruq',
      'dhuhr',
      'duhr',
      'asr',
      'maghrib',
      'magrib',
      'isha',
      'ishaa',
      'imsak'
    ];

    for (final name in prayers) {
      final String channelIdWithSpace = 'Pre $name ';
      final String silentChannelIdWithSpace = 'Silent Pre $name ';
      final String channelId = 'Pre $name';
      final String silentChannelId = 'Silent Pre $name';

      await android.deleteNotificationChannel(channelIdWithSpace);
      await android.deleteNotificationChannel(silentChannelIdWithSpace);
      await android.deleteNotificationChannel(channelId);
      await android.deleteNotificationChannel(silentChannelId);
    }
    Log.i('Orphaned pre-notification channels deletion completed.');
  } catch (e, s) {
    Log.e('Failed deleting orphaned notification channels', error: e, stackTrace: s);
  }
}