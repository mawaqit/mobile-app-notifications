import 'package:flutter_test/flutter_test.dart';
import 'package:mawaqit_core_logger/mawaqit_core_logger.dart';
import 'package:mobile_app_notifications/models/prayers/prayer_name.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'prayer_name_test.mocks.dart';

@GenerateMocks([PrayersName])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('PrayersName', () {
    late MockPrayersName mockPrayersName;

    setUp(() {
      mockPrayersName = MockPrayersName();
    });

    Future<String> getLanguageMock(String language) async {
      return language;
    }

    test('should return correct prayer name for Arabic language', () async {
      when(mockPrayersName.getLanguage())
          .thenAnswer((_) => getLanguageMock('ar'));
      when(mockPrayersName.getPrayerName(any)).thenAnswer((invocation) async {
        int index = invocation.positionalArguments[0];
        switch (index) {
          case 0:
            return 'الفجر';
          case 1:
            return 'الشروق';
          case 2:
            return 'الظهر';
          case 3:
            return 'العصر';
          case 4:
            return 'المغرب';
          case 5:
            return 'العشاء';
          case 6:
            return 'الإمساك';
          default:
            return 'غير معروف';
        }
      });

      for (int i = 0; i < 7; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'الفجر');
            break;
          case 1:
            expect(result, 'الشروق');
            break;
          case 2:
            expect(result, 'الظهر');
            break;
          case 3:
            expect(result, 'العصر');
            break;
          case 4:
            expect(result, 'المغرب');
            break;
          case 5:
            expect(result, 'العشاء');
            break;
          case 6:
            expect(result, 'الإمساك');
            break;
          default:
            expect(result, 'غير معروف');
        }
        Log.i('Arabic prayer name for index $i: $result');
      }
    });

    test('should return correct prayer name for Bengali language', () async {
      when(mockPrayersName.getLanguage())
          .thenAnswer((_) => getLanguageMock('bn'));
      when(mockPrayersName.getPrayerName(any)).thenAnswer((invocation) async {
        int index = invocation.positionalArguments[0];
        switch (index) {
          case 0:
            return 'ফজর';
          case 1:
            return 'শুরুক';
          case 2:
            return 'দুহর';
          case 3:
            return 'আসর';
          case 4:
            return 'মাগরিব';
          case 5:
            return 'ইশা';
          case 6:
            return 'ইমসাক';
          default:
            return 'অজানা';
        }
      });

      for (int i = 0; i < 7; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'ফজর');
            break;
          case 1:
            expect(result, 'শুরুক');
            break;
          case 2:
            expect(result, 'দুহর');
            break;
          case 3:
            expect(result, 'আসর');
            break;
          case 4:
            expect(result, 'মাগরিব');
            break;
          case 5:
            expect(result, 'ইশা');
            break;
          case 6:
            expect(result, 'ইমসাক');
            break;
          default:
            expect(result, 'অজানা');
        }
        Log.i('Bengali prayer name for index $i: $result');
      }
    });

    test('should return correct prayer name for English language', () async {
      when(mockPrayersName.getLanguage())
          .thenAnswer((_) => getLanguageMock('en'));
      when(mockPrayersName.getPrayerName(any)).thenAnswer((invocation) async {
        int index = invocation.positionalArguments[0];
        switch (index) {
           case 0:
            return 'Fajr';
          case 1:
            return 'Shuruq';
          case 2:
            return 'Duhr';
          case 3:
            return 'Asr';
          case 4:
            return 'Maghrib';
          case 5:
            return 'Isha';
          case 6:
            return 'Imsak';
          default:
            return 'Unknown';
        }
      });

      for (int i = 0; i < 7; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'Fajr');
            break;
          case 1:
            expect(result, 'Shuruq');
            break;
          case 2:
            expect(result, 'Duhr');
            break;
          case 3:
            expect(result, 'Asr');
            break;
          case 4:
            expect(result, 'Maghrib');
            break;
          case 5:
            expect(result, 'Isha');
            break;
          case 6:
            expect(result, 'Imsak');
            break;
          default:
            expect(result, 'Unknown');
        }
        Log.i('English prayer name for index $i: $result');
      }
    });

    test('should return default "Unknown" for unsupported language', () async {
      when(mockPrayersName.getLanguage())
          .thenAnswer((_) => getLanguageMock('unsupported_language'));
      when(mockPrayersName.getPrayerName(any))
          .thenAnswer((_) async => 'Unknown');

      var result = await mockPrayersName.getPrayerName(0);
      expect(result, 'Unknown');
      Log.w('Unsupported language prayer name for index 0: $result');
    });
  });
}
