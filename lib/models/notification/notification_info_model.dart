class NotificationInfoModel {
  String? mosqueName, sound, prayerName, soundType;
  DateTime? time;
  int notificationBeforeAthan;
  int alarmId;
  bool playInSilent;

  NotificationInfoModel({
    required this.mosqueName,
    required this.sound,
    required this.prayerName,
    required this.time,
    this.notificationBeforeAthan = 0,
    this.alarmId = 0,
    required this.soundType,
    this.playInSilent = false,
  });
}
