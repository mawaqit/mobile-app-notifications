class NotificationInfoModel {
  String? mosqueName, sound, prayerName, soundType;
  DateTime? time;
  int notificationBeforeAthan;
  int alarmId;
  bool playInSilent;
  bool customVolumeEnabled;
  int adhanVolume;
  bool useFullAdhanIOS;
  bool muteWithVolumeKeys;
  String preSound;
  String preSoundType;
  bool preUseFullAdhanIOS;
  NotificationInfoModel({
    required this.mosqueName,
    required this.sound,
    required this.prayerName,
    required this.time,
    this.notificationBeforeAthan = 0,
    this.alarmId = 0,
    required this.soundType,
    this.playInSilent = false,
    this.customVolumeEnabled = false,
    this.adhanVolume = 100,
    this.useFullAdhanIOS = false,
    this.muteWithVolumeKeys = false,
    this.preSound = 'DEFAULT',
    this.preSoundType = 'none',
    this.preUseFullAdhanIOS = false,
  });

  /// Whether the pre-notification plays an adhan instead of the default beep.
  bool get hasPreAdhan =>
      preSound.isNotEmpty && preSound != 'DEFAULT' && preSound != 'SILENT';
}
