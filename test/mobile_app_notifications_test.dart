// import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/mobile_app_notifications.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'mobile_app_notifications_test.mocks.dart';

// @GenerateMocks([AwesomeNotifications, ScheduleAdhan])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ringAlarm', () {
    // late MockAwesomeNotifications mockAwesomeNotifications;
    // late MockScheduleAdhan mockScheduleAdhan;
    setUp(() {
      // mockAwesomeNotifications = MockAwesomeNotifications();
      // mockScheduleAdhan = MockScheduleAdhan();
      // AwesomeNotifications().initialize(
      //   'resource://drawable/logo',
      //   [
      //     NotificationChannel(
      //       channelKey: 'pre_notif',
      //       channelName: 'mawaqit',
      //       channelDescription: 'mawaqit_channel',
      //       importance: NotificationImportance.Max,
      //       defaultColor: const Color(0xFF9D50DD),
      //       ledColor: Colors.white,
      //       playSound: true,
      //       soundSource: null,
      //       enableVibration: false,
      //       icon: 'resource://drawable/logo',
      //       onlyAlertOnce: true,
      //       criticalAlerts: true,
      //       defaultRingtoneType: DefaultRingtoneType.Notification,
      //     )
      //   ],
      // );
    });

    test('should handle pre-notification correctly', () async {
      final data = {
        'index': 0,
        'sound': 'mawaqit_id',
        'mosque': 'Test Mosque',
        'prayer': 'Test Prayer',
        'time': '10',
        'isPreNotification': true,
        'minutesToAthan': '10 minutes',
        'notificationBeforeShuruq': 0,
      };

      // when(mockAwesomeNotifications.createNotification(
      //   content: anyNamed('content'),
      // )).thenAnswer((_) async => true);
      //
      // ringAlarm(1, data);
      //
      // verifyNever(mockAwesomeNotifications.createNotification(
      //   content: argThat(
      //     isA<NotificationContent>().having(
      //       (content) => content.title,
      //       'title',
      //       '10 minutes Test Prayer',
      //     ),
      //     named: 'content',
      //   ),
      // ));
    });

    test('should handle adhan notification correctly', () async {
      final data = {
        'index': 0,
        'sound': 'mawaqit_id.mp3',
        'mosque': 'Test Mosque',
        'prayer': 'Test Prayer',
        'time': '10',
        'isPreNotification': false,
        'minutesToAthan': '10 minutes',
        'notificationBeforeShuruq': 0,
      };
      //
      // when(mockAwesomeNotifications.createNotification(
      //   content: anyNamed('content'),
      // )).thenAnswer((_) async => true);
      //
      // when(mockScheduleAdhan.schedule()).thenReturn(true);
      //
      // ringAlarm(1, data);
      //
      // verifyNever(mockAwesomeNotifications.createNotification(
      //   content: argThat(
      //     isA<NotificationContent>().having(
      //       (content) => content.title,
      //       'title',
      //       'Test Prayer  10',
      //     ),
      //     named: 'content',
      //   ),
      // ));
    });
  });
}
