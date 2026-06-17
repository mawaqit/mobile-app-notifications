import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

class DeviceRingtoneMode {
  /// True when the ringer is silent OR vibrate — i.e. no audible ringtone.
  /// Vibrate is treated as "muted" because the user has signalled they don't
  /// want a regular ringer sound; the adhan toggle escalates to alarm stream
  /// in both cases.
  static Future<bool> isMuted() async {
    try {
      RingerModeStatus ringerStatus = await SoundMode.ringerModeStatus;
      return ringerStatus == RingerModeStatus.vibrate ||
          ringerStatus == RingerModeStatus.silent;
    } catch (e, stackTrace) {
      Log.e('Error reading ringer mode: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}
