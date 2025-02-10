import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SoundType {
  none,
  customSound,
  systemSound,
}

class PrayerNotification {
  final int? prayer;
  final String? mosqueUuid;
  final int? notificationBeforeAthan;
  final String? notificationSound;
  final SoundType soundType; // custom_sound , no_type , system_sound

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

  PrayerNotification(this.prayer, this.mosqueUuid, this.notificationBeforeAthan,
      this.notificationSound , this.soundType);

  PrayerNotification.fromJson(Map<String, dynamic> json)
      : prayer = json['prayer'],
        mosqueUuid = json['mosqueUuid'],
        notificationBeforeAthan = json['notificationBeforeAthan'],
        notificationSound = json['notificationSound'],
        soundType = SoundType.values.firstWhere((e) => e.name == json['soundType'], orElse: () => SoundType.none); // Default to 'none' if missing

  Map<String, dynamic> toJson() {
    return {
      'prayer': prayer,
      'mosqueUuid': mosqueUuid,
      'notificationBeforeAthan': notificationBeforeAthan,
      'notificationSound': notificationSound,
      'soundType': soundType.name, // Store as a string
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
