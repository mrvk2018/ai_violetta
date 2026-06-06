import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';

/// Locale-aware spoken formatting for zero-latency time and date utilities.
class LocalUtilityFormatter {
  LocalUtilityFormatter._();

  static const List<String> timeKeywords = <String>[
    'сколько время',
    'который час',
    '지금 몇시',
    '몇 시',
    'время',
    '시간',
  ];

  static const List<String> dateKeywords = <String>[
    'какой сегодня день',
    '몇 월',
    '몇 일',
    'число',
    'дата',
    '날짜',
  ];

  static const List<String> _ruWeekdays = <String>[
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];

  static const List<String> _ruMonthsGenitive = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> _koWeekdays = <String>[
    '월요일',
    '화요일',
    '수요일',
    '목요일',
    '금요일',
    '토요일',
    '일요일',
  ];

  static const Map<int, String> _ruDayOrdinals = <int, String>{
    1: 'первое',
    2: 'второе',
    3: 'третье',
    4: 'четвертое',
    5: 'пятое',
    6: 'шестое',
    7: 'седьмое',
    8: 'восьмое',
    9: 'девятое',
    10: 'десятое',
    11: 'одиннадцатое',
    12: 'двенадцатое',
    13: 'тринадцатое',
    14: 'четырнадцатое',
    15: 'пятнадцатое',
    16: 'шестнадцатое',
    17: 'семнадцатое',
    18: 'восемнадцатое',
    19: 'девятнадцатое',
    20: 'двадцатое',
    21: 'двадцать первое',
    22: 'двадцать второе',
    23: 'двадцать третье',
    24: 'двадцать четвертое',
    25: 'двадцать пятое',
    26: 'двадцать шестое',
    27: 'двадцать седьмое',
    28: 'двадцать восьмое',
    29: 'двадцать девятое',
    30: 'тридцатое',
    31: 'тридцать первое',
  };

  static bool matchesDateQuery(String normalizedText) {
    return _matchesKeyword(normalizedText, dateKeywords);
  }

  static bool matchesTimeQuery(String normalizedText) {
    return _matchesKeyword(normalizedText, timeKeywords);
  }

  static String formatTime(DateTime now, ViolettaAppLocale locale) {
    if (locale.isKorean) {
      final String dayPeriod = now.hour < 12 ? '오전' : '오후';
      final int hour12 = now.hour == 0
          ? 12
          : (now.hour > 12 ? now.hour - 12 : now.hour);
      return '지금은 $dayPeriod $hour12시 ${now.minute}분입니다';
    }

    return 'Сейчас ${_ruHours(now.hour)} ${_ruMinutes(now.minute)}';
  }

  static String formatDate(DateTime now, ViolettaAppLocale locale) {
    if (locale.isKorean) {
      final String weekday = _koWeekdays[now.weekday - 1];
      return '오늘은 ${now.year}년 ${now.month}월 ${now.day}일 $weekday입니다';
    }

    final String weekday = _ruWeekdays[now.weekday - 1];
    final String dayOrdinal =
        _ruDayOrdinals[now.day] ?? '${now.day}-е';
    final String month = _ruMonthsGenitive[now.month - 1];
    return 'Сегодня $weekday, $dayOrdinal $month';
  }

  static String formatAlarmConfirmation(
    int hour,
    int minute,
    ViolettaAppLocale locale,
  ) {
    if (locale.isKorean) {
      final String dayPeriod = hour < 12 ? '오전' : '오후';
      final int hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final String paddedMinute = minute.toString().padLeft(2, '0');
      return '알람이 $dayPeriod $hour12시 $paddedMinute분으로 설정되었습니다';
    }

    final String paddedHour = hour.toString().padLeft(2, '0');
    final String paddedMinute = minute.toString().padLeft(2, '0');
    return 'Будильник установлен на $paddedHour:$paddedMinute';
  }

  static bool _matchesKeyword(String normalizedText, List<String> keywords) {
    for (final String keyword in keywords) {
      if (normalizedText.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String _ruHours(int hour) {
    final int mod10 = hour % 10;
    final int mod100 = hour % 100;
    if (mod10 == 1 && mod100 != 11) {
      return '$hour час';
    }
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$hour часа';
    }
    return '$hour часов';
  }

  static String _ruMinutes(int minute) {
    final int mod10 = minute % 10;
    final int mod100 = minute % 100;
    if (mod10 == 1 && mod100 != 11) {
      return '$minute минута';
    }
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$minute минуты';
    }
    return '$minute минут';
  }
}
