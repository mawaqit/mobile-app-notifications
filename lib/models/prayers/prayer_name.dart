import 'package:shared_preferences/shared_preferences.dart';

class PrayersName {
  Future<String> getPrayerName(int index) async {
    String language = await getLanguage();

    switch (language) {
      case 'ar':
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
      case 'bn':
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
      case 'de':
        switch (index) {
          case 0:
            return 'Fadjr';
          case 2:
            return 'Dohr';
          case 3:
            return 'Assr';
          case 4:
            return 'Maghrib';
          case 5:
            return 'Ishaa';
          default:
            return 'Άγνωστος';
        }
      case 'en':
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
      case 'es':
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
            return 'Ishaa';
          default:
            return 'Desconocido';
        }
      case 'fr':
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
            return 'Inconnu';
        }
      case 'id':
        switch (index) {
          case 0:
            return 'Subuh';
          case 2:
            return 'Duhr';
          case 3:
            return 'Ashar';
          case 4:
            return 'Maghrib';
          case 5:
            return 'Isya.';
          default:
            return 'Tidak diketahui';
        }
      case 'it':
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
            return 'Ishaa';
          default:
            return 'Sconosciuto';
        }
      case 'nl':
        switch (index) {
          case 0:
            return 'Fadjr';
          case 2:
            return 'Dhoehr';
          case 3:
            return "'Asr";
          case 4:
            return 'Maghrib';
          case 5:
            return "'Ishaa";
          default:
            return 'Onbekend';
        }
      case 'pl':
        switch (index) {
          case 0:
            return 'Fadżr';
          case 2:
            return 'Zuhr';
          case 3:
            return 'Asr';
          case 4:
            return 'Maghrib';
          case 5:
            return 'Isza';
          default:
            return 'Nieznany';
        }
      case 'ru':
        switch (index) {
          case 0:
            return 'Фаджр';
          case 2:
            return 'Зухр';
          case 3:
            return 'Аср';
          case 4:
            return 'Магриб';
          case 5:
            return 'Иша';
          default:
            return 'Неизвестный';
        }
      case 'tr':
        switch (index) {
          case 0:
            return 'Sabah';
          case 2:
            return 'Öğlen';
          case 3:
            return 'İkindi';
          case 4:
            return 'Akşam';
          case 5:
            return 'Yatsı';
          default:
            return 'Bilinmeyen';
        }
      case 'ur':
        switch (index) {
          case 0:
            return 'فجر';
          case 2:
            return 'دہر';
          case 3:
            return 'عصر';
          case 4:
            return 'مغرب';
          case 5:
            return 'عشاء';
          default:
            return 'نامعلوم';
        }
      default:
        return 'Unknown';
    }
  }

  Future<String> getStringText() async {
    String language = await getLanguage();
    switch (language) {
      case 'ar':
        return 'دقيقة لأذان';
      case 'bn':
        return 'এথান থেকে মিনিট';
      case 'de':
        return 'Minuten zu Athan';
      case 'en':
        return 'minutes to athan';
      case 'es':
        return 'minutos para athan';
      case 'fr':
        return 'minutes à athan';
      case 'id':
        return 'menit ke athan';
      case 'it':
        return 'minuti per athan';
      case 'nl':
        return 'minuten voor athan';
      case 'pl':
        return 'Minuty do Adan';
      case 'ru':
        return 'минут до азана';
      case 'tr':
        return 'Ezanına bir dakika';
      case 'ur':
        return 'اتھن کے لیے منٹ';

      default:
        return 'minutes to athan';
    }
  }

   Future<String> getLanguage() async {
    final db = await SharedPreferences.getInstance();
    return db.getString('MAWAQIT_LANGUAGE') ?? '';
  }
}
