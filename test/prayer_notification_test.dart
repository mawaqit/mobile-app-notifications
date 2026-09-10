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
  });
}
