import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

class DeviceRingtoneMode {
// We'll use a heuristic based on volume changes
  static Future<bool> isMuted() async {
    try {
      RingerModeStatus ringerStatus = await SoundMode.ringerModeStatus;
      return ringerStatus == RingerModeStatus.vibrate || ringerStatus == RingerModeStatus.silent;
    } catch (e, stackTrace) {
      Log.e('Error checking vibration: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}