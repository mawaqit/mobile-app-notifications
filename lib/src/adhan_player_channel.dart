import 'package:flutter/services.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mawaqit_mobile_i18n/gen_l10n/app_localizations.dart';
import 'package:mobile_app_notifications/helpers/device_ringtone_mode.dart';
import 'package:mobile_app_notifications/helpers/localization_helper.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_notification.dart';

const MethodChannel _adhanPlayerChannel =
    MethodChannel('com.mawaqit.notifications/adhan_player');

/// Resolves which Android audio stream the adhan plays on, based on the
/// per-prayer `playInSilent` preference and the current ringer state.
///
///   * playInSilent == false                    → ringtone (respects mute)
///   * playInSilent == true,  ringer normal     → ringtone (plays normally)
///   * playInSilent == true,  ringer muted/vibe → alarm    (bypasses mute)
Future<String> _resolveStreamUsage(bool playInSilent) async {
  if (!playInSilent) return 'ringtone';
  try {
    final isMuted = await DeviceRingtoneMode.isMuted();
    return isMuted ? 'alarm' : 'ringtone';
  } catch (e, s) {
    Log.e('Failed reading ringer mode — defaulting to alarm',
        error: e, stackTrace: s);
    return 'alarm';
  }
}

/// Plays the adhan through the native foreground service (MediaPlayer) on the
/// stream resolved from `playInSilent` + current ringer state.
Future<void> playAdhanNative({
  required String sound,
  required SoundType soundType,
  required String title,
  required String body,
  required bool playInSilent,
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

  final streamUsage = await _resolveStreamUsage(playInSilent);
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
