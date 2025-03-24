import 'package:flutter/services.dart';

enum DeviceRingtoneMode {silent , vibrate , normal}

class MethodChannelRepo {
  static const CHANNEL_SYNCHRONIZER = 'com.mawaqit.app/app_group';
  static const fetchDeviceRingtoneModeEvent = 'fetchDeviceRingtoneMode';

  static Future<String> checkDeviceMode() async {
    const platform = MethodChannel(CHANNEL_SYNCHRONIZER);
    String currentDeviceRingtoneMode = await platform.invokeMethod(fetchDeviceRingtoneModeEvent);
    return currentDeviceRingtoneMode;
  }
}