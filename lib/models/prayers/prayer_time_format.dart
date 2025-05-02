import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrayerTimeFormat {
  String settings24HoursFormat = '24_HOURS_FORMAT_SETTINGS';
  String languageCode = "en";
  bool format24 = true;

  Future<bool> get24HoursFormatSetting() async {
    final db = await SharedPreferences.getInstance();
    db.reload();
    return db.getBool(settings24HoursFormat) ?? true;
  }

  String formatHour(String? value) {
    if (value == null) return '';
    if (format24) return value;
    var d = value.split(':');
    int modulo = 12;
    if (d[0] == '12') modulo = 13;
    String h = (int.parse(d[0]) % modulo).toString();
    String m = int.parse(d[1]).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String getAPM(String? value) {
    if (value == null) return '';
    if (format24) return '';
    var d = value.split(':');
    int h = int.parse(d[0]);
    if (h >= 12) {
      if (languageCode == 'ar') {
        return 'م';
      }
      return 'PM';
    }
    if (languageCode == 'ar') {
      return 'ص';
    }
    return 'AM';
  }

  Future<String> getFormattedPrayerTime(String prayerTime) async {
    try {
      format24 = await get24HoursFormatSetting();
      languageCode = await PrayersName().getLanguage();
      if (!format24) {
        String timeIn12HourFormat = formatHour(prayerTime);
        String amOrPm = getAPM(prayerTime);
        return "$timeIn12HourFormat $amOrPm";
      }
    } catch (e) {
      print("Exception in getFormattedPrayerTime: $e");
    }

    return prayerTime;
  }
}
