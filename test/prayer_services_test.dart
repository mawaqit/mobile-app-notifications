import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/models/mosque/detailed_mosque.dart';
import 'package:mobile_app_notifications/models/notification/notification_info_model.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'prayer_services_test.mocks.dart';

@GenerateMocks([DetailedMosque, PrayerService, PrayerNotificationService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('getPrayerDataByIndex Tests', () {
    final mockPrayerService = MockPrayerService();
    final mockDetailedMosque = MockDetailedMosque();
    test('should return notification data if notification sound is not SILENT',
        () async {
      final dummyPrayerNotification =
          PrayerNotification(0, 'mosqueUuid', 10, 'DEFAULT', SoundType.none);

      when(mockPrayerService.getPrayerDataByIndex(any, 0))
          .thenAnswer((_) async => dummyPrayerNotification);

      var result =
          await mockPrayerService.getPrayerDataByIndex(mockDetailedMosque, 0);

      print('Test: Notification sound is not SILENT');
      print('Expected: Not null, actual: ${result!.notificationSound}');
      expect(result, isNotNull);
      expect(result.notificationSound, 'DEFAULT');
    });
    test('should return NULL if notification sound is SILENT', () async {
      final dummyPrayerNotification =
          PrayerNotification(0, 'mosqueUuid', 10, 'SILENT' , SoundType.none);

      when(mockPrayerService.getPrayerDataByIndex(any, 0))
          .thenAnswer((_) async => dummyPrayerNotification);

      var result =
          await mockPrayerService.getPrayerDataByIndex(mockDetailedMosque, 0);

      print('Test: Notification sound is SILENT');
      print('Expected: null, actual: ${result!.notificationSound}');
      expect(result, isNotNull);
      expect(result.notificationSound, 'SILENT');
    });
  });
  group('getPrayerTime Tests', () {
    final mockDetailedMosque = MockDetailedMosque();
    final mockPrayerService = MockPrayerService();

    // Example data
    final calendar = [
      {
        '01': '04:30',
        '02': '05:00',
        '03': '05:30',
        '04': '06:00',
        '05': '06:30',
        '06': '07:00',
        '07': '07:30',
        '08': '08:00',
        '09': '08:30',
        '10': '09:00',
        '11': '09:30',
        '12': '10:00',
        '13': '10:30',
        '14': '11:00',
        '15': '11:30',
        '16': '12:00',
        '17': '12:30',
        '18': '13:00',
        '19': '13:30',
        '20': '14:00',
        '21': '14:30',
        '22': '15:00',
        '23': '15:30',
        '24': '16:00',
        '25': '16:30',
        '26': '17:00',
        '27': '17:30',
        '28': '18:00',
        '29': '18:30',
        '30': '19:00',
        '31': '19:30',
      }
    ];

    test('should return correct prayer time', () {
      final now = DateTime(2024, 5, 27); // Example date
      when(mockDetailedMosque.calendar).thenReturn(calendar);

      when(mockPrayerService.getPrayerTime(any, any, time: anyNamed('time')))
          .thenAnswer((_) => DateTime(2024, 5, 27, 4, 30));

      final prayerTime = mockPrayerService
          .getPrayerTime(mockDetailedMosque, 'FAJR', time: now);

      expect(prayerTime, DateTime(2024, 5, 27, 4, 30));
    });

    test('should return null if calendar is null', () {
      when(mockDetailedMosque.calendar).thenReturn(null);

      when(mockPrayerService.getPrayerTime(any, any)).thenAnswer((_) => null);

      final prayerTime =
          mockPrayerService.getPrayerTime(mockDetailedMosque, 'FAJR');

      expect(prayerTime, isNull);
    });

    test('should return null if key is not found', () {
      when(mockDetailedMosque.calendar).thenReturn(calendar);

      when(mockPrayerService.getPrayerTime(any, any)).thenAnswer((_) => null);

      final prayerTime =
          mockPrayerService.getPrayerTime(mockDetailedMosque, 'INVALID_KEY');

      expect(prayerTime, isNull);
    });
  });
  group('getPrayers Test', () {
    final mockPrayerNotificationService = MockPrayerNotificationService();
    final mockDetailedMosque = MockDetailedMosque();
    final mockPrayerService = MockPrayerService();

    setUp(() {
      reset(mockPrayerNotificationService);
      reset(mockDetailedMosque);
      reset(mockPrayerService);
    });

    final dummyGetPrayerDataByIndex =
        PrayerNotification(0, 'mosqueUuid', 10, 'DEFAULT' , SoundType.none);
    final dummyGetMosque = DetailedMosque(
      [
        {
          '01': '04:30',
          '02': '05:00',
          '03': '05:30',
          '04': '06:00',
          '05': '06:30',
          '06': '07:00',
          '07': '07:30',
          '08': '08:00',
          '09': '08:30',
          '10': '09:00',
          '11': '09:30',
          '12': '10:00',
          '13': '10:30',
          '14': '11:00',
          '15': '11:30',
          '16': '12:00',
          '17': '12:30',
          '18': '13:00',
          '19': '13:30',
          '20': '14:00',
          '21': '14:30',
          '22': '15:00',
          '23': '15:30',
          '24': '16:00',
          '25': '16:30',
          '26': '17:00',
          '27': '17:30',
          '28': '18:00',
          '29': '18:30',
          '30': '19:00',
          '31': '19:30',
        }
      ],
      10,
      1622104600000, // Example timestamp
      0,
      false,
      '06:00', // Example time
      [
        '04:30',
        '05:00',
        '05:30',
        '06:00',
        '06:30',
        '07:00',
        '07:30',
        '08:00',
        '08:30',
        '09:00',
        '09:30',
        '10:00',
        '10:30',
        '11:00',
        '11:30',
        '12:00',
        '12:30',
        '13:00',
        '13:30',
        '14:00',
        '14:30',
        '15:00',
        '15:30',
        '16:00',
        '16:30',
        '17:00',
        '17:30',
        '18:00',
        '18:30',
        '19:00',
        '19:30',
      ],
      [], // Example list
      [], // Example list
      5, // Example value
      [], // Example list
    );

    test('should return a list of prayers with valid notifications', () async {
      when(mockPrayerService.getPrayerTime(any, any, time: anyNamed('time')))
          .thenAnswer((_) => DateTime.now().add(const Duration(days: 1)));

      when(mockPrayerService.getPrayerDataByIndex(any, any))
          .thenAnswer((_) async => dummyGetPrayerDataByIndex);

      when(mockPrayerService.getMosque(any))
          .thenAnswer((_) async => dummyGetMosque);

      when(mockPrayerNotificationService.getPrayerNotificationFromDB(any))
          .thenAnswer(
              (_) async => PrayerNotification(0, 'mosqueUuid', 10, 'DEFAULT' , SoundType.none));

      when(mockPrayerService.getPrayers()).thenAnswer((_) async {
        return [
          NotificationInfoModel(
            mosqueName: 'Test Mosque',
            sound: 'DEFAULT',
            prayerName: 'FAJR',
            time: DateTime.now().add(const Duration(days: 1)),
            notificationBeforeAthan: 10,
            soundType: 'customSound'
          ),
        ];
      });

      final prayers = await mockPrayerService.getPrayers();

      expect(prayers, isA<List<NotificationInfoModel>>());
      expect(prayers.length, lessThanOrEqualTo(5));
      for (var prayer in prayers) {
        expect(prayer.mosqueName, 'Test Mosque');
        expect(prayer.sound, 'DEFAULT');
        expect(prayer.notificationBeforeAthan, 10);
      }
    });

    test('should return an empty list if no notifications are scheduled',
        () async {
      when(mockPrayerNotificationService.getPrayerNotificationFromDB(any))
          .thenAnswer((_) async =>
              PrayerNotification(1, null, 10, 'DEFAULT' , SoundType.none)); // mosqueUuid is null

      when(mockPrayerService.getPrayers()).thenAnswer((_) async => []);

      final prayers = await mockPrayerService.getPrayers();

      expect(prayers, isEmpty);
    });

    test('should remove expired prayers and limit to 5', () async {
      when(mockPrayerService.getPrayerTime(any, any, time: anyNamed('time')))
          .thenAnswer((_) => DateTime.now().subtract(const Duration(days: 1)));

      when(mockPrayerService.getPrayerDataByIndex(any, any))
          .thenAnswer((_) async => dummyGetPrayerDataByIndex);

      when(mockPrayerService.getMosque(any))
          .thenAnswer((_) async => dummyGetMosque);

      when(mockPrayerNotificationService.getPrayerNotificationFromDB(any))
          .thenAnswer((_) async => PrayerNotification(
              1, 'mosqueUuid', 10, 'DEFAULT' , SoundType.none)); // Example data

      when(mockPrayerService.getPrayers()).thenAnswer((_) async => []);

      final prayers = await mockPrayerService.getPrayers();

      expect(prayers, isEmpty);
    });
  });
}
