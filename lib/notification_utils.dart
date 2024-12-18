import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationUtils {
  static Future<void> initializeNotificationChannels() async {
    await AwesomeNotifications().initialize(
      'resource://drawable/logo', // App icon
      [
        NotificationChannel(
          channelKey: 'default_channel',
          channelName: 'Default Notifications',
          channelDescription: 'Notifications with default sound',
          importance: NotificationImportance.Max,
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          playSound: true,
          enableVibration: true,
          onlyAlertOnce: true,
        ),
        NotificationChannel(
          channelKey: 'silent_channel',
          channelName: 'Silent Notifications',
          channelDescription: 'Notifications with no sound',
          importance: NotificationImportance.Max,
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          playSound: false, // No sound for silent notifications
          enableVibration: true,
          onlyAlertOnce: true,
        ),
        NotificationChannel(
          channelKey: 'adhan_channel',
          channelName: 'Adhan Notifications',
          channelDescription: 'Notifications with dynamic adhan sounds',
          importance: NotificationImportance.Max,
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          playSound: true,
          enableVibration: true,
          onlyAlertOnce: true,
        ),
      ],
    );
  }
}
