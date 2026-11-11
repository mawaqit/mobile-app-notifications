import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app_notifications/models/alarm_authorization_state.dart';
import 'package:mobile_app_notifications/src/ios_scheduler.dart';

void main() {
  group('AlarmAuthorizationState.fromName', () {
    test('parses the native state names', () {
      expect(AlarmAuthorizationState.fromName('authorized'),
          AlarmAuthorizationState.authorized);
      expect(AlarmAuthorizationState.fromName('denied'),
          AlarmAuthorizationState.denied);
      expect(AlarmAuthorizationState.fromName('notDetermined'),
          AlarmAuthorizationState.notDetermined);
    });

    test('treats a missing or unknown value as unsupported', () {
      expect(AlarmAuthorizationState.fromName(null),
          AlarmAuthorizationState.unsupported);
      expect(AlarmAuthorizationState.fromName('somethingNew'),
          AlarmAuthorizationState.unsupported);
    });
  });

  group('canScheduleFullAdhan', () {
    test('only an authorized Alarms permission goes to AlarmKit', () {
      expect(canScheduleFullAdhan(AlarmAuthorizationState.authorized), isTrue);
    });

    test('every other state falls back to a normal notification', () {
      for (final state in [
        AlarmAuthorizationState.denied,
        AlarmAuthorizationState.notDetermined,
        AlarmAuthorizationState.unsupported,
      ]) {
        expect(canScheduleFullAdhan(state), isFalse, reason: state.name);
      }
    });
  });
}
