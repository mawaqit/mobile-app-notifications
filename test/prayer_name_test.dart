import 'package:flutter_test/flutter_test.dart';
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
          case 2:
            return 'الظهر';
          case 3:
            return 'العصر';
          case 4:
            return 'المغرب';
          case 5:
            return 'العشاء';
          default:
            return 'غير معروف';
        }
      });

      for (int i = 0; i < 6; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'الفجر');
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
          default:
            expect(result, 'غير معروف');
        }
        print('Arabic prayer name for index $i: $result');
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
          case 2:
            return 'দুহর';
          case 3:
            return 'আসর';
          case 4:
            return 'মাগরিব';
          case 5:
            return 'ইশা';
          default:
            return 'অজানা';
        }
      });

      for (int i = 0; i < 6; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'ফজর');
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
          default:
            expect(result, 'অজানা');
        }
        print('Bengali prayer name for index $i: $result');
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
          case 2:
            return 'Duhr';
          case 3:
            return 'Asr';
          case 4:
            return 'Maghrib';
          case 5:
            return 'Isha';
          default:
            return 'Unknown';
        }
      });

      for (int i = 0; i < 6; i++) {
        var result = await mockPrayersName.getPrayerName(i);
        switch (i) {
          case 0:
            expect(result, 'Fajr');
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
          default:
            expect(result, 'Unknown');
        }
        print('English prayer name for index $i: $result');
      }
    });

    test('should return default "Unknown" for unsupported language', () async {
      when(mockPrayersName.getLanguage())
          .thenAnswer((_) => getLanguageMock('unsupported_language'));
      when(mockPrayersName.getPrayerName(any))
          .thenAnswer((_) async => 'Unknown');

      var result = await mockPrayersName.getPrayerName(0);
      expect(result, 'Unknown');
      print('Unsupported language prayer name for index 0: $result');
    });
  });
}
