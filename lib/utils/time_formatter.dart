import 'package:shamsi_date/shamsi_date.dart';

class TimeFormatter {
  static String format(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) return '$hours ساعت و $minutes دقیقه';
    if (minutes > 0) return '$minutes دقیقه و $remainingSeconds ثانیه';
    return '$remainingSeconds ثانیه';
  }

  static String clock(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }

  static String persianDigits(String value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < latin.length; i++) {
      value = value.replaceAll(latin[i], persian[i]);
    }
    return value;
  }

  static String jalaliDate(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return persianDigits('${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
  }

  static String jalaliDateTime(DateTime date) =>
      '${jalaliDate(date)}  ${persianDigits('${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}')}';
}
