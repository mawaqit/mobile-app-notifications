import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/models/notification/notification_info_model.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mosqueUuid = 'test-mosque-uuid';
  const adhan = 'adhan_makkah_fajr_android.mp3';

  // Every day of every month: Fajr, Shuruq, Duhr, Asr, Maghrib, Isha.
  final calendar = List.generate(
    12,
    (_) => {
      for (var day = 1; day <= 31; day++)
        day.toString().padLeft(2, '0'): [
          '05:00',
          '06:30',
          '13:00',
          '16:00',
          '19:00',
          '21:00',
        ],
    },
  );

  String record(int prayer) => jsonEncode(PrayerNotification(
        prayer,
        mosqueUuid,
        15,
        'DEFAULT',
        SoundType.none,
        preNotificationSound: adhan,
        preNotificationSoundType: SoundType.customSound,
        preUseFullAdhanIOS: true,
      ).toJson());

  setUp(() {
    SharedPreferences.setMockInitialValues({
      mosqueUuid: jsonEncode({'name': 'Test Mosque', 'calendar': calendar}),
      'FAJR_NOTIFICATION': record(0),
      'DUHR_NOTIFICATION': record(2),
    });
  });

  test('Fajr carries its adhan pre-notification sound', () async {
    final prayers = await PrayerService().getPrayers();
    final fajr = prayers.firstWhere((p) => p.alarmId ~/ 1000000 == 0);

    expect(fajr.hasPreAdhan, isTrue);
    expect(fajr.preSound, adhan);
    expect(fajr.preSoundType, 'customSound');
    expect(fajr.preUseFullAdhanIOS, isTrue);
  });

  test('other prayers keep the beep even if their record holds an adhan',
      () async {
    final prayers = await PrayerService().getPrayers();
    final duhr = prayers.firstWhere((p) => p.alarmId ~/ 1000000 == 2);

    expect(duhr.hasPreAdhan, isFalse);
    expect(duhr.preSound, 'DEFAULT');
    expect(duhr.preUseFullAdhanIOS, isFalse);
  });

  test('hasPreAdhan is false for the beep and silent', () {
    NotificationInfoModel info(String preSound) => NotificationInfoModel(
          mosqueName: 'Test Mosque',
          sound: 'DEFAULT',
          prayerName: 'Fajr',
          time: DateTime.now(),
          soundType: 'none',
          preSound: preSound,
        );

    expect(info('DEFAULT').hasPreAdhan, isFalse);
    expect(info('SILENT').hasPreAdhan, isFalse);
    expect(info('').hasPreAdhan, isFalse);
    expect(info(adhan).hasPreAdhan, isTrue);
  });
}
