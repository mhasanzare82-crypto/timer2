import 'dart:convert';

import 'package:shamsi_date/shamsi_date.dart';

/// Persian-calendar representation used for every persisted calendar date.
/// Format: yyyy/MM/dd HH:mm:ss.SSS (Jalali calendar).
class JalaliDateStorage {
  JalaliDateStorage._();

  static String encode(DateTime value) {
    final j = Jalali.fromDateTime(value);
    return '${j.year.toString().padLeft(4, '0')}/'
        '${j.month.toString().padLeft(2, '0')}/'
        '${j.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}.'
        '${value.millisecond.toString().padLeft(3, '0')}';
  }

  /// Reads current Jalali strings and legacy epoch-millisecond backups/rows.
  static DateTime decode(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is! String) {
      throw FormatException('تاریخ ذخیره‌شده معتبر نیست: $value');
    }
    final match = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,3}))?)?)?$',
    ).firstMatch(value.trim());
    if (match == null) throw FormatException('قالب تاریخ شمسی نامعتبر است: $value');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    final second = int.tryParse(match.group(6) ?? '') ?? 0;
    final millis = int.parse((match.group(7) ?? '0').padRight(3, '0'));
    final date = Jalali(year, month, day).toDateTime();
    return DateTime(date.year, date.month, date.day, hour, minute, second, millis);
  }

  static Object? normalizeJsonDates(Object? value, [String? key]) {
    const dateKeys = {
      'startedAt', 'firstStartedAt', 'startAt', 'endAt', 'scheduledAt',
      'createdAt', 'activityDate', 'exportedAt',
    };
    if (value is Map) {
      return value.map((k, v) => MapEntry(
        k.toString(), normalizeJsonDates(v, k.toString()),
      ));
    }
    if (value is List) {
      return value.map((v) => normalizeJsonDates(v)).toList();
    }
    if (key != null && dateKeys.contains(key) && (value is num || value is String)) {
      try {
        return encode(decode(value));
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  static String normalizeStateJson(String key, String value) {
    if (key != 'multi_activity_timers_v1' &&
        key != 'countdown_timer_state_v2' &&
        key != 'user_reminders') {
      return value;
    }
    try {
      final decoded = jsonDecode(value);
      return jsonEncode(normalizeJsonDates(decoded));
    } catch (_) {
      return value;
    }
  }
}
