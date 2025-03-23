// ignore_for_file: avoid_print, unused_local_variable

library mobile_app_notifications;

import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_time_format.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzl;
import 'package:timezone/timezone.dart' as tz;

var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void ringAlarm(int id, Map<String, dynamic> data) async {
  print('from ringAlarm');
  String sound = data['sound'];
  String mosque = data['mosque'];
  String prayer = data['prayer'];
  String time = data['time'];
  SoundType soundType = SoundType.values.firstWhere((e) => e.name == data['sound_type']);
  bool isPreNotification = data['isPreNotification'];
  String minutesToAthan = data['minutesToAthan'];
  int notificationBeforeShuruq = data['notificationBeforeShuruq'];

  String? adhanSound;
  String notificationTitle;
  try {
    String formattedTime = await PrayerTimeFormat().getFormattedPrayerTime(time);

    if (isPreNotification) {
      print('for pre notification');
      notificationTitle = '$time $minutesToAthan $prayer';
    } else {
      print('for adhan notification');
      if (notificationBeforeShuruq != 0) {
        String inText = await PrayersName().getInText();
        String minutes = await PrayersName().getMinutesText();
        print('notificationBeforeShuruq : $notificationBeforeShuruq');
        notificationTitle = '$prayer $inText $notificationBeforeShuruq $minutes';
      } else {
        print('notificationBeforeShuruq : $notificationBeforeShuruq');
        notificationTitle = '$prayer  $formattedTime';
      }

      if (sound == 'DEFAULT') {
        adhanSound = null;
      } else if (soundType == SoundType.customSound) {
        adhanSound = sound.substring(0, sound.length - 4);
      } else {
        adhanSound = sound;
      }
    }
    print('adhan sound: $adhanSound');
    print('sound type from user: $soundType');

    // Assign per-prayer channel ID
    String baseChannelId = prayer.toLowerCase(); // e.g., 'fajr', 'dhuhr'
    String channelName = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan';
    String channelId = isPreNotification ? 'Pre $baseChannelId ' : '$baseChannelId Adhan $sound';

    print(" ----- ------- -- - - - --- -channelId: $channelId");
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      // isPreNotification ? 'pre_notif' : adhanSound ?? 'DEFAULT',
      // 'mawaqit',
      // channelDescription: 'mawaqit_channel',
      channelId,
      channelName,
      channelDescription: isPreNotification ? 'Pre Adhan notifications for $prayer' : 'Adhan notifications for $prayer',
      importance: Importance.max,
      priority: Priority.high,
      playSound: !isPreNotification,
      sound: isPreNotification
          ? null
          : soundType == SoundType.customSound
              ? RawResourceAndroidNotificationSound(adhanSound)
              : UriAndroidNotificationSound(adhanSound ?? ''),
      enableVibration: true,
      largeIcon: const DrawableResourceAndroidBitmap('logo'),
      icon: 'logo',
      onlyAlertOnce: false,
      ticker: 'ticker',
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone, // Helps bypass silent mode
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.alarm,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      notificationTitle,
      mosque,
      platformChannelSpecifics,
    );

    ScheduleAdhan scheduleAdhan = ScheduleAdhan.instance;
    scheduleAdhan.schedule();
  } catch (e, t) {
    print('an error occurs');
    print(t);
    print(e);
  }
}


class ScheduleAdhan {
  // Private constructor
  ScheduleAdhan._privateConstructor() {
    newAlarmIds = [];
    isScheduling = false;
  }

  // Singleton instance
  static final ScheduleAdhan _instance = ScheduleAdhan._privateConstructor();

  // Getter to access the single instance
  static ScheduleAdhan get instance => _instance;

  // The list that should be initialized only once
  late List<String> newAlarmIds;
  late bool isScheduling;

  Future<bool> checkIOSNotificationPermissions() async {
    final iosPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final permissionStatus = await iosPlugin?.checkPermissions();
    if (permissionStatus == null) {
      print('Could not get permission status');
      return false;
    } else {
      print('OverAll: ${permissionStatus.isEnabled}');
      print('Alert: ${permissionStatus.isAlertEnabled}');
      print('Badge: ${permissionStatus.isBadgeEnabled}');
      print('Sound: ${permissionStatus.isSoundEnabled}');
      return permissionStatus.isEnabled && permissionStatus.isAlertEnabled && permissionStatus.isBadgeEnabled && permissionStatus.isSoundEnabled;
    }
  }

  schedule() {
    if (Platform.isAndroid) {
      scheduleAndroid();
    } else if (Platform.isIOS) {
      scheduleIOS();
    }
  }

  flushAlarmIdList() => newAlarmIds = [];

  scheduleAndroid() async {
    print('from schedule');

    if (isScheduling) {
      print("Scheduling in progress, please wait until it's completed...");
      return;
    }
    isScheduling = true;
    SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String> previousAlarms = prefs.getStringList('alarmIds') ?? [];

    for (String alarmId in previousAlarms) {
      int id = int.parse(alarmId);
      await AndroidAlarmManager.cancel(id);
      print('Cancelled Alarm Id: $id');
    }
    flushAlarmIdList();
    await prefs.remove('alarmIds');
    await prefs.setStringList('alarmIds', []);

    var prayersList = await PrayerService().getPrayers();

    for (var i = 0; i < prayersList.length; i++) {
      var prayer = prayersList[i];

      String minutesToAthan = await PrayersName().getStringText();

      //for Pre notification
      var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));

      if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
        var id = "1${prayer.alarmId}";
        newAlarmIds.add(id);
        try {
          AndroidAlarmManager.oneShotAt(preNotificationTime, int.parse(id), ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'sound': 'mawaqit_id',
                'mosque': prayer.mosqueName,
                'prayer': prayer.prayerName,
                'time': prayer.notificationBeforeAthan.toString(),
                'isPreNotification': true,
                'minutesToAthan': minutesToAthan,
                'notificationBeforeShuruq': 0,
                'sound_type': prayer.soundType
              });
          print('Pre Notification scheduled for ${prayer.prayerName} at : $preNotificationTime Id: $id');
        } catch (e, t) {
          print(t);
          print(e);
        }
      }
      //for Adhan notification
      String prayerTime = DateFormat('HH:mm').format(prayer.time!);
      DateTime notificationTime;
      int notificationBeforeShuruq;

      int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');
      if (index == 1) {
        notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;

        notificationTime = prayer.time!.subtract(Duration(minutes: notificationBeforeShuruq));
      } else {
        notificationTime = prayer.time!;
        notificationBeforeShuruq = 0;
      }
      if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
        newAlarmIds.add(prayer.alarmId.toString());
        try {
          AndroidAlarmManager.oneShotAt(notificationTime, prayer.alarmId, ringAlarm,
              alarmClock: true,
              allowWhileIdle: true,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              params: {
                'index': index,
                'sound': prayer.sound,
                'mosque': prayer.mosqueName,
                'prayer': prayer.prayerName,
                'time': prayerTime,
                'isPreNotification': false,
                'minutesToAthan': '',
                'notificationBeforeShuruq': notificationBeforeShuruq,
                'sound_type': prayer.soundType
              });
          print('Sound ${prayer.sound} Notification scheduled for ${prayer.prayerName} at : $notificationTime Id: ${prayer.alarmId}');
          await prefs.setStringList('alarmIds', newAlarmIds);
        } catch (e, t) {
          print(t);
          print(e);
        }
      }
    }
    isScheduling = false;

    print(newAlarmIds.toList());
  }

  scheduleIOS() async {
    try {
      // Clear all scheduled notifications
      await flutterLocalNotificationsPlugin.cancelAll();
      print('Cleared previous Notifications');

      // Retrieve SharedPreferences and prayers list
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var prayersList = await PrayerService().getPrayers();
      int i = 0, j = 0;

      if (prayersList.isEmpty) {
        return; // Exit early if there are no prayers
      } else {
        // Loop to schedule up to 63 notifications
        while (i < prayersList.length && j < 63) {
          var prayer = prayersList[i];
          int index = await PrayersName().getPrayerIndex(prayer.prayerName ?? '');

          // Fetch prayer translations and preset strings
          String translatedPrayerName = prayer.prayerName ?? 'Unknown';
          String minutesToAthan = await PrayersName().getStringText();
          String inText = await PrayersName().getInText();
          String minutes = await PrayersName().getMinutesText();

          // Pre-notification logic
          var preNotificationTime = prayer.time!.subtract(Duration(minutes: prayer.notificationBeforeAthan));

          /// PRE NOTIFICATION
          if (prayer.notificationBeforeAthan != 0 && preNotificationTime.isAfter(DateTime.now())) {
            String title = '${prayer.notificationBeforeAthan} $minutesToAthan $translatedPrayerName';
            await iosNotificationSchedular(
              int.parse(("1${prayer.alarmId}")),
              preNotificationTime,
              title,
              prayer.mosqueName,
              null,
            );
            print('Pre Notification scheduled for ${prayer.prayerName} at: $preNotificationTime Id: ${1 + prayer.alarmId}');
            j++;
          }

          // Main Athan notification logic
          String prayerTime = DateFormat('HH:mm').format(prayer.time!);
          DateTime notificationTime = prayer.time!;
          String formatedPrayerTime = await PrayerTimeFormat().getFormattedPrayerTime(prayerTime);
          String notificationTitle = '$translatedPrayerName $formatedPrayerTime';
          int notificationBeforeShuruq;

          // Handle Shuruq timing if the prayer is Fajr (index == 1)
          if (index == 1) {
            notificationBeforeShuruq = prefs.getInt('notificationBeforeShuruq') ?? 0;
            notificationTime = prayer.time!.subtract(Duration(minutes: notificationBeforeShuruq));
            notificationTitle = '$translatedPrayerName $inText $notificationBeforeShuruq $minutes';
          }

          if (prayer.sound != 'SILENT' && notificationTime.isAfter(DateTime.now())) {
            if (prayer.soundType == SoundType.systemSound.name) {
              String? soundFile;

              if (prayer.sound?.isNotEmpty == true) {
                soundFile = await PrayerService().getDeviceSound(prayer.sound ?? "");
              }

              await iosNotificationSchedular(
                prayer.alarmId,
                notificationTime,
                notificationTitle,
                prayer.mosqueName,
                soundFile ?? prayer.sound,
              );
            } else {
              await iosNotificationSchedular(
                prayer.alarmId,
                notificationTime,
                notificationTitle,
                prayer.mosqueName,
                prayer.sound,
              );
            }
            print('Notification scheduled for ${prayer.prayerName} at: $notificationTime with Id: ${prayer.alarmId}');
            j++;
            // }
          }

          // Move to the next prayer
          i++;
        }
      }
    } catch (e, s) {
      // Enhanced error logging
      print('Error in scheduleIOS: $e');
      print('$s');
    }
    List<PendingNotificationRequest> allPendingNotification = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    print('All scheduling notifications length:  ${allPendingNotification.length}');
    for (var element in allPendingNotification) {
      print('element length:  ${element.title} , body: ${element.payload}');
      print('------------------------------------------------------------------------------------------------------');
    }
  }

  Future<void> initAlarmManager() async {
    await AndroidAlarmManager.initialize();
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

  Future<void> iosNotificationSchedular(int? id, DateTime date, String? title, String? body, String? soundId) async {
    print('--------------------------------------------------schedule sound id : $soundId --------------------------------------------------');
    try {
      final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
          sound: soundId == 'DEFAULT' ? null : soundId, presentSound: true, presentAlert: true, presentBadge: true, interruptionLevel: InterruptionLevel.critical);

      final platformChannelSpecifics = NotificationDetails(
        iOS: iOSPlatformChannelSpecifics,
      );

      tzl.initializeTimeZones();
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      final location = tz.getLocation(timeZoneName);
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      final scheduledDate = tz.TZDateTime.from(date, location);

      tz.TZDateTime now = tz.TZDateTime.now(location);
      if (now.isAfter(scheduledDate)) return;

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id!,
        title,
        body,
        scheduledDate,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: 'scheudle date: $scheduledDate , sound id: $soundId',
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
    } catch (e, s) {
      print('ERROR: $e');
      print('stack trace: $s');
    }
  }
}
