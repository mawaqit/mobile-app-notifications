import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';

void main() {
  group('PrayerNotification plugin tests', () {
    test('default muteWithVolumeKeys is false', () {
      final notif = PrayerNotification(
        0,
        'test-mosque-uuid',
        0,
        'adhan_makkah_fajr_android.mp3',
        SoundType.customSound,
      );

      expect(notif.muteWithVolumeKeys, isFalse);
    });

    test('toJson and fromJson preserves muteWithVolumeKeys', () {
      final notif = PrayerNotification(
        2,
        'test-mosque-uuid',
        0,
        'adhan_afassy_android.mp3',
        SoundType.customSound,
        playInSilent: true,
        customVolumeEnabled: true,
        adhanVolume: 90,
        useFullAdhanIOS: false,
        muteWithVolumeKeys: true,
      );

      final json = notif.toJson();
      expect(json['muteWithVolumeKeys'], isTrue);

      final fromJson = PrayerNotification.fromJson(json);
      expect(fromJson.muteWithVolumeKeys, isTrue);
      expect(fromJson.adhanVolume, 90);
      expect(fromJson.playInSilent, isTrue);
    });

    test('pre-notification sound defaults to the beep', () {
      final notif = PrayerNotification(
        0,
        'test-mosque-uuid',
        10,
        'adhan_makkah_fajr_android.mp3',
        SoundType.customSound,
      );

      expect(notif.preNotificationSound, 'DEFAULT');
      expect(notif.preNotificationSoundType, SoundType.none);
      expect(notif.preUseFullAdhanIOS, isFalse);
    });

    test('toJson and fromJson preserves the pre-notification sound', () {
      final notif = PrayerNotification(
        0,
        'test-mosque-uuid',
        15,
        'DEFAULT',
        SoundType.none,
        preNotificationSound: 'adhan_makkah_fajr_android.mp3',
        preNotificationSoundType: SoundType.customSound,
        preUseFullAdhanIOS: true,
      );

      final fromJson = PrayerNotification.fromJson(notif.toJson());
      expect(fromJson.preNotificationSound, 'adhan_makkah_fajr_android.mp3');
      expect(fromJson.preNotificationSoundType, SoundType.customSound);
      expect(fromJson.preUseFullAdhanIOS, isTrue);
    });

    test('records saved before the pre-notification sound read as the beep',
        () {
      final fromJson = PrayerNotification.fromJson({
        'prayer': 0,
        'mosqueUuid': 'test-mosque-uuid',
        'notificationBeforeAthan': 10,
        'notificationSound': 'DEFAULT',
        'soundType': 'none',
      });

      expect(fromJson.preNotificationSound, 'DEFAULT');
      expect(fromJson.preNotificationSoundType, SoundType.none);
      expect(fromJson.preUseFullAdhanIOS, isFalse);
    });
  });
}
