import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app_notifications/models/mosque/mosque_model.dart';

part 'detailed_mosque.g.dart';

@JsonSerializable(explicitToJson: true)
class DetailedMosque extends Mosque {
  final int? hijriAdjustment;
  final bool? hijriDateForceTo30;
  final int? imsakNbMinBeforeFajr;
  final int? updatedAt;

  final List? calendar;
  final String? shuruq;
  final List? times;
  final List? iqama;
  final List? iqamaCalendar;
  final List? imsakCalendar;

  final int? proximity;

  final bool iqamaEnabled;

  static const virtual = 'VIRTUAL';

  bool get isVirtual {
    return uuid == virtual;
  }

  DetailedMosque(
      this.calendar,
      this.imsakNbMinBeforeFajr,
      this.updatedAt,
      this.hijriAdjustment,
      this.hijriDateForceTo30,
      this.shuruq,
      this.times,
      this.iqama,
      this.iqamaCalendar,
      this.proximity,
      this.imsakCalendar,
      [this.iqamaEnabled = true]);

  factory DetailedMosque.fromJson(Map<String, dynamic> json) =>
      _$DetailedMosqueFromJson(json);

  Map<String, dynamic> toJson() => _$DetailedMosqueToJson(this);
}
