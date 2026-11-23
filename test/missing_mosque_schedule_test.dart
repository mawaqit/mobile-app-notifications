import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/prayer_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fajrNotificationFor(String mosqueUuid) => jsonEncode({
      'prayer': 0,
      'mosqueUuid': mosqueUuid,
      'notificationBeforeAthan': 0,
      'notificationSound': 'DEFAULT',
      'soundType': 'none',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // mawaqit/mobile-app#3358: when a favorite mosque is removed but its
  // notification settings stay behind, its stored data is gone and every
  // prayer time lookup returns null. getPrayers must still finish.
  test('getPrayers finishes when the notification mosque has no stored data', () async {
    SharedPreferences.setMockInitialValues({
      'FAJR_NOTIFICATION': _fajrNotificationFor('deleted-mosque'),
    });

    final prayers = await PrayerService().getPrayers();

    expect(prayers, isEmpty);
  });

  test('getPrayers finishes when the stored mosque has no calendar', () async {
    SharedPreferences.setMockInitialValues({
      'FAJR_NOTIFICATION': _fajrNotificationFor('mosque-without-calendar'),
      'mosque-without-calendar': jsonEncode({'uuid': 'mosque-without-calendar', 'name': 'No calendar'}),
    });

    final prayers = await PrayerService().getPrayers();

    expect(prayers, isEmpty);
  });
}
