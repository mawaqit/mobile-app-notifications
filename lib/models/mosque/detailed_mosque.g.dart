// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detailed_mosque.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DetailedMosque _$DetailedMosqueFromJson(Map<String, dynamic> json) =>
    DetailedMosque(
      json['calendar'] as List<dynamic>?,
      (json['imsakNbMinBeforeFajr'] as num?)?.toInt(),
      (json['updatedAt'] as num?)?.toInt(),
      (json['hijriAdjustment'] as num?)?.toInt(),
      json['hijriDateForceTo30'] as bool?,
      json['shuruq'] as String?,
      json['times'] as List<dynamic>?,
      json['iqama'] as List<dynamic>?,
      json['iqamaCalendar'] as List<dynamic>?,
      (json['proximity'] as num?)?.toInt(),
      json['imsakCalendar'] as List<dynamic>?,
      json['iqamaEnabled'] as bool? ?? true,
    )
      ..uuid = json['uuid'] as String?
      ..name = json['name'] as String?
      ..label = json['label'] as String?
      ..phone = json['phone'] as String?
      ..email = json['email'] as String?
      ..site = json['site'] as String?
      ..localisation = json['localisation'] as String?
      ..longitude = (json['longitude'] as num?)?.toDouble()
      ..latitude = (json['latitude'] as num?)?.toDouble()
      ..image = json['image'] as String?
      ..url = json['url'] as String?
      ..paymentWebsite = json['paymentWebsite'] as String?
      ..jumua = json['jumua'] as String?
      ..jumua2 = json['jumua2'] as String?
      ..womenSpace = json['womenSpace'] as bool?
      ..janazaPrayer = json['janazaPrayer'] as bool?
      ..aidPrayer = json['aidPrayer'] as bool?
      ..aidPrayerTime = json['aidPrayerTime'] as String?
      ..aidPrayerTime2 = json['aidPrayerTime2'] as String?
      ..childrenCourses = json['childrenCourses'] as bool?
      ..adultCourses = json['adultCourses'] as bool?
      ..ramadanMeal = json['ramadanMeal'] as bool?
      ..handicapAccessibility = json['handicapAccessibility'] as bool?
      ..ablutions = json['ablutions'] as bool?
      ..parking = json['parking'] as bool?
      ..jumuaAsDuhr = json['jumuaAsDuhr'] as bool?
      ..lastModifiedHeaderTimes = json['lastModifiedHeaderTimes'] as String?
      ..lastModifiedHeaderInfo = json['lastModifiedHeaderInfo'] as String?
      ..lastModifiedHeaderHijri = json['lastModifiedHeaderHijri'] as String?
      ..countryCode = json['countryCode'] as String?;

Map<String, dynamic> _$DetailedMosqueToJson(DetailedMosque instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'name': instance.name,
      'label': instance.label,
      'phone': instance.phone,
      'email': instance.email,
      'site': instance.site,
      'localisation': instance.localisation,
      'longitude': instance.longitude,
      'latitude': instance.latitude,
      'image': instance.image,
      'url': instance.url,
      'paymentWebsite': instance.paymentWebsite,
      'jumua': instance.jumua,
      'jumua2': instance.jumua2,
      'womenSpace': instance.womenSpace,
      'janazaPrayer': instance.janazaPrayer,
      'aidPrayer': instance.aidPrayer,
      'aidPrayerTime': instance.aidPrayerTime,
      'aidPrayerTime2': instance.aidPrayerTime2,
      'childrenCourses': instance.childrenCourses,
      'adultCourses': instance.adultCourses,
      'ramadanMeal': instance.ramadanMeal,
      'handicapAccessibility': instance.handicapAccessibility,
      'ablutions': instance.ablutions,
      'parking': instance.parking,
      'jumuaAsDuhr': instance.jumuaAsDuhr,
      'lastModifiedHeaderTimes': instance.lastModifiedHeaderTimes,
      'lastModifiedHeaderInfo': instance.lastModifiedHeaderInfo,
      'lastModifiedHeaderHijri': instance.lastModifiedHeaderHijri,
      'countryCode': instance.countryCode,
      'hijriAdjustment': instance.hijriAdjustment,
      'hijriDateForceTo30': instance.hijriDateForceTo30,
      'imsakNbMinBeforeFajr': instance.imsakNbMinBeforeFajr,
      'updatedAt': instance.updatedAt,
      'calendar': instance.calendar,
      'shuruq': instance.shuruq,
      'times': instance.times,
      'iqama': instance.iqama,
      'iqamaCalendar': instance.iqamaCalendar,
      'imsakCalendar': instance.imsakCalendar,
      'proximity': instance.proximity,
      'iqamaEnabled': instance.iqamaEnabled,
    };
