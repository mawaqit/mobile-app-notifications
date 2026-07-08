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
