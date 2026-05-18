import 'package:flutter/services.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:mobile_app_notifications/helpers/localization_helper.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the user's audio stream choice.
/// Allowed values: "alarm" (default), "ringtone", "notification", "media".
const String kAdhanStreamPrefKey = 'adhan_audio_stream';

const MethodChannel _adhanPlayerChannel =
    MethodChannel('com.mawaqit.notifications/adhan_player');

const Set<String> _kAllowedStreamUsages = {
  'alarm',
  'ringtone',
  'notification',
  'media',
};

Future<String> _resolveAdhanStreamUsage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(kAdhanStreamPrefKey);
    if (value != null && _kAllowedStreamUsages.contains(value)) {
      return value;
    }
  } catch (e, s) {
    Log.e('resolve stream usage failed', error: e, stackTrace: s);
  }
  return 'alarm';
}

/// Plays the adhan through the native foreground service (MediaPlayer)
/// on the user's chosen audio stream. Falls back to a notification-based
/// sound if the native channel call fails.
Future<void> playAdhanNative({
  required String sound,
  required SoundType soundType,
  required String title,
  required String body,
}) async {
  String soundArg;
  if (sound == 'DEFAULT') {
    soundArg = '';
  } else if (soundType == SoundType.customSound) {
    // Strip the file extension — service uses resources.getIdentifier on a bare name
    soundArg = sound.length > 4 ? sound.substring(0, sound.length - 4) : sound;
  } else {
    soundArg = sound;
  }

  final streamUsage = await _resolveAdhanStreamUsage();
  AppLocalizations localizations = await LocalizationHelper.getLocalization();

  String channelName = localizations.adhan;
  String channelDescription = localizations.plays_adhan_prayer_arrives;
  String stopLabel = localizations.stop;
  String defaultTitle = localizations.adhan;

  try {
    await _adhanPlayerChannel.invokeMethod<void>('playAdhan', {
      'sound': soundArg,
      'soundType': soundType.name,
      'streamUsage': streamUsage,
      'title': title,
      'body': body,
      'channelName': channelName,
      'channelDescription': channelDescription,
      'stopLabel': stopLabel,
      'defaultTitle': defaultTitle,
    });
    Log.i('Adhan dispatched to native player (usage=$streamUsage)');
  } catch (e, s) {
    Log.e('Native adhan playback failed — no audible fallback',
        error: e, stackTrace: s);
  }
}
