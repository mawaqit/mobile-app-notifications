import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SoundType {
  none,
  customSound,
  systemSound,
}

/// Per-prayer adhan volume bounds. The floor is enforced so the adhan can
/// never be fully muted via the in-app slider (a muted adhan is almost always
/// a mistake — users have play-in-silent / SILENT sound for that).
const int kMinAdhanVolume = 10;
const int kMaxAdhanVolume = 100;

class PrayerNotification {
  final int? prayer;
  final String? mosqueUuid;
  final int? notificationBeforeAthan;
  final String? notificationSound;
  final SoundType soundType; // custom_sound , no_type , system_sound

  /// Android-only: when true, the adhan escalates to the alarm stream if the
  /// phone is muted (silent or vibrate), so it's still heard. When false, the
  /// adhan plays on the ringtone stream and respects muting like a normal
  /// notification. Defaults to true.
  final bool playInSilent;

  /// Android-only: when true, the adhan playback temporarily overrides the
  /// system volume of the stream it plays on (ring/alarm) with [adhanVolume],
  /// restoring the original level once playback finishes. When false, the adhan
  /// plays at whatever the device volume already is. Defaults to false.
  final bool customVolumeEnabled;

  /// Android-only: per-prayer adhan volume as a percentage in
  /// [kMinAdhanVolume]..[kMaxAdhanVolume]. Only applied when
  /// [customVolumeEnabled] is true. Defaults to [kMaxAdhanVolume].
  final int adhanVolume;



  static getDBPrayerKeyByPrayer(int? prayer) {
    switch (prayer) {
      case 0:
        {
          return 'FAJR_NOTIFICATION';
        }
      case 2:
        {
          return 'DUHR_NOTIFICATION';
        }
      case 3:
        {
          return 'ASR_NOTIFICATION';
        }
      case 4:
        {
          return 'MAGRIB_NOTIFICATION';
        }
      case 5:
        {
          return 'ISHAA_NOTIFICATION';
        }
    }
  }

  static Future<bool> savePrayerNotificationToDB(
      PrayerNotification prayerNotification) async {
    final prayerKey = getDBPrayerKeyByPrayer(prayerNotification.prayer);
    final db = await SharedPreferences.getInstance();
    return db.setString(prayerKey, jsonEncode(prayerNotification.toJson()));
  }

  static Future<bool> removePrayerNotificationFromDB(String prayerKey) async {
    final db = await SharedPreferences.getInstance();
    return db.remove(prayerKey);
  }

  PrayerNotification(
    this.prayer,
    this.mosqueUuid,
    this.notificationBeforeAthan,
    this.notificationSound,
    this.soundType, {
    this.playInSilent = false,
    this.customVolumeEnabled = false,
    this.adhanVolume = kMaxAdhanVolume,
  });

  PrayerNotification.fromJson(Map<String, dynamic> json)
      : prayer = json['prayer'],
        mosqueUuid = json['mosqueUuid'],
        notificationBeforeAthan = json['notificationBeforeAthan'],
        notificationSound = json['notificationSound'],
        soundType = SoundType.values.firstWhere(
            (e) => e.name == json['soundType'],
            orElse: () => SoundType.none),
        // Default off — users opt in to "play through silent mode" explicitly.
        playInSilent = json['playInSilent'] ?? false,
        customVolumeEnabled = json['customVolumeEnabled'] ?? false,
        adhanVolume = json['adhanVolume'] ?? kMaxAdhanVolume;

  Map<String, dynamic> toJson() {
    return {
      'prayer': prayer,
      'mosqueUuid': mosqueUuid,
      'notificationBeforeAthan': notificationBeforeAthan,
      'notificationSound': notificationSound,
      'soundType': soundType.name,
      'playInSilent': playInSilent,
      'customVolumeEnabled': customVolumeEnabled,
      'adhanVolume': adhanVolume,
    };
  }
}

class PrayerNotificationService {
  Future<PrayerNotification> getPrayerNotificationFromDB(
      String prayerKey) async {
    final db = await SharedPreferences.getInstance();
    final prayerNotificationString = db.getString(prayerKey);
    if (prayerNotificationString == null) {
      return PrayerNotification.fromJson(<String, dynamic>{});
    }
    return PrayerNotification.fromJson(jsonDecode(prayerNotificationString));
  }
}
