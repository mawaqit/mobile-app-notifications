import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared `flutter_local_notifications` instance used by every code path that
/// posts, schedules, cancels, or queries notifications in this package.
var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

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
