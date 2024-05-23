class NotificationInfoModel {
  String? mosqueName, sound, prayerName;
  DateTime? time;
  int notificationBeforeAthan;
  int alarmId;

  NotificationInfoModel({
    required this.mosqueName,
    required this.sound,
    required this.prayerName,
    required this.time,
    this.notificationBeforeAthan = 0,
    this.alarmId = 0,
  });
}
