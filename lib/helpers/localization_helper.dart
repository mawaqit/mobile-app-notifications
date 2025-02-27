import 'package:flutter/widgets.dart';
import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationHelper {
  static Future<AppLocalizations> getLocalization() async {
    final prefs = await SharedPreferences.getInstance();
    String languageCode = prefs.getString('MAWAQIT_LANGUAGE') ?? 'en'; // Default to English
    Locale locale = Locale(languageCode);
    return AppLocalizations.delegate.load(locale);
  }
}