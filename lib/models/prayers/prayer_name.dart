import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/localization_helper.dart';

class PrayersName {
  Future<String> getPrayerName(int index) async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();

    switch (index) {
      case 0:
        return localizations.fajr;
      case 1:
        return localizations.shuruq;
      case 2:
        return localizations.duhr;
      case 3:
        return localizations.asr;
      case 4:
        return localizations.maghrib;
      case 5:
        return localizations.isha;
      case 6:
        return localizations.imsak;
      default:
        return 'Unknown';
    }
  }

  Future<String> getStringText() async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    return localizations.minutes_to_athan;
  }

  Future<String> getInText() async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    return localizations.in_;
  }

  Future<String> getMinutesText() async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    return localizations.minutes;
  }

  Future<String> getLanguage() async {
    final db = await SharedPreferences.getInstance();
    return db.getString('MAWAQIT_LANGUAGE') ?? 'en';
  }
}
