import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';

class DeviceRingtoneMode {
// We'll use a heuristic based on volume changes
  static Future<bool> isLikelyVibrationMode() async {
    try {
      VolumeController volumeController = VolumeController.instance;
      bool isMuted = await volumeController.isMuted();
      return isMuted;
    } catch (e) {
      print('Error checking vibration: $e');
      return false;
    }
  }
}