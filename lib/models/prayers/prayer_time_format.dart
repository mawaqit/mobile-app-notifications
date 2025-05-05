import 'package:shared_preferences/shared_preferences.dart';

class PrayerTimeFormat {
  String settings24HoursFormat = '24_HOURS_FORMAT_SETTINGS';

  String formatHour(String? time) {
    if (time == null) return '';
    var d = time.split(':');
    int modulo = 12;
    if (d[0] == '12') modulo = 13;
    String h = (int.parse(d[0]) % modulo).toString();
    String m = int.parse(d[1]).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String getAPM({String? time, required String languageCode}) {
    if (time == null) return '';
    var d = time.split(':');
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

  String getFormattedPrayerTime({required String prayerTime, required bool timeFormat, required String selectedLanguage}) {
    try {
      if (!timeFormat) {
        String timeIn12HourFormat = formatHour(prayerTime);
        String amOrPm = getAPM(time: prayerTime, languageCode: selectedLanguage);
        if (timeIn12HourFormat.isNotEmpty && amOrPm.isNotEmpty) {
          return "$timeIn12HourFormat $amOrPm";
        }
      }
    } catch (e) {
      print("Exception in getFormattedPrayerTime: $e");
    }
    return prayerTime;
  }

  Future<bool> get24HoursFormatSetting() async {
    final db = await SharedPreferences.getInstance();
    db.reload();
    bool format24 = db.getBool(settings24HoursFormat) ?? true;
    return format24;
  }
}
