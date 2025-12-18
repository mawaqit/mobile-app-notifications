import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/localization_helper.dart';

class PrayersName {
  Future<int> getPrayerIndex(String prayer) async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();

    switch (prayer) {
      case var _ when prayer == localizations.fajr:
        return 0;
      case var _ when prayer == localizations.shuruq:
        return 1;
      case var _ when prayer == localizations.duhr:
        return 2;
      case var _ when prayer == localizations.asr:
        return 3;
      case var _ when prayer == localizations.maghrib:
        return 4;
      case var _ when prayer == localizations.isha:
        return 5;
      case var _ when prayer == localizations.imsak:
        return 6;
      default:
        return 0;
    }
  }

  Future<String> getStringText(int minuteToAthan) async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    if (await getLanguage() == 'ar' && minuteToAthan > 10) {
      return 'دقيقة حتى آذان';
    }
    return localizations.minutes_to_athan;
  }

  Future<String> getInText() async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    return localizations.in_;
  }

  Future<String> getMinutesText(int minuteToAthan) async {
    AppLocalizations localizations = await LocalizationHelper.getLocalization();
    if (await getLanguage() == 'ar' && minuteToAthan <= 10) {
      return 'دقائق';
    }
    return localizations.minutes;
  }

  Future<String> getLanguage() async {
    final db = await SharedPreferences.getInstance();
    return db.getString('MAWAQIT_LANGUAGE') ?? 'en';
  }
}
