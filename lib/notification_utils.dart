import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationUtils {
  static Future<void> initializeNotificationChannels() async {
    try {
      AwesomeNotifications().initialize(
        'resource://drawable/logo', // Icon for notifications
        [
          NotificationChannel(
            channelKey: 'pre_notif',
            channelName: 'Pre-Notification Channel',
            channelDescription: 'Notifications before prayer times',
            importance: NotificationImportance.High,
            defaultColor: const Color(0xFF9D50DD),
            ledColor: Colors.white,
            playSound: true,
            enableVibration: true,
            criticalAlerts: true,
            onlyAlertOnce: true,
          ),
          NotificationChannel(
            channelKey: 'DEFAULT',
            channelName: 'Default Channel',
            channelDescription: 'Adhan and other prayer notifications',
            importance: NotificationImportance.Max,
            defaultColor: const Color(0xFF9D50DD),
            ledColor: Colors.white,
            playSound: true,
            enableVibration: true,
            criticalAlerts: true,
            soundSource: 'resource://raw/default_adhan',
            onlyAlertOnce: true,
          ),
        ],
      );
      print("Notification channels initialized successfully.");
    } catch (e) {
      print("Error initializing notification channels: $e");
    }
  }
}
