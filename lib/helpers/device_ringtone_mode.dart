import 'package:flutter/services.dart';
import 'package:volume_control/volume_control.dart';

class DeviceRingtoneMode {
// We'll use a heuristic based on volume changes
  static Future<bool> isLikelyVibrationMode() async {
    try {
      double volume = await VolumeControl.volume;
      // This is a heuristic - not perfect, but best we can do without native
      // Assuming vibration mode might be when volume is very low but not zero
      return volume > 0.0 && volume <= 0.1;
    } catch (e) {
      print('Error checking vibration: $e');
      return false;
    }
  }
}